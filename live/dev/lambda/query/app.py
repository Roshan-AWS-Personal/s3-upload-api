import os, json, io, time, random, collections, re
from typing import Any, Dict, List, Optional, cast
from urllib.parse import urlparse

import boto3
import faiss  # type: ignore
import numpy as np
from botocore.exceptions import ClientError

# -----------------------------
# Env & clients
# -----------------------------
BUCKET         = os.environ["S3_BUCKET"]
INDEX_PREFIX   = os.environ.get("INDEX_PREFIX", "indexes/latest/")
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", "ap-southeast-2")
EMBED_MODEL_ID = os.environ.get("EMBED_MODEL_ID", "amazon.titan-embed-text-v2:0")
CHAT_MODEL_ID  = os.environ.get("CHAT_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")
EMBED_DIM      = int(os.environ.get("EMBED_DIM", "1024"))
TOP_K          = int(os.environ.get("TOP_K", "8"))
MAX_DOCS       = int(os.environ.get("MAX_DOCS", "3"))
MAX_TOKENS     = int(os.environ.get("MAX_TOKENS", "400"))
CTX_CHAR_BUDGET = int(os.environ.get("CTX_CHAR_BUDGET", "1800"))

s3 = boto3.client("s3")
bedrock = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)

# -----------------------------
# Globals (hot reload in Lambda)
# -----------------------------
INDEX: Optional[faiss.Index] = None
META: List[Dict[str, Any]] = []
INDEX_ETAG: Optional[str] = None
META_ETAG: Optional[str]  = None

# -----------------------------
# Utilities
# -----------------------------
def _resp(status: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization",
            "Access-Control-Allow-Methods": "POST,OPTIONS",
        },
        "body": json.dumps(body),
    }

def _jsonloads_safe(s: str) -> Dict[str, Any]:
    try:
        v = json.loads(s)
        return v if isinstance(v, dict) else {}
    except Exception:
        return {}

# -----------------------------
# Bedrock helpers
# -----------------------------
def _invoke_json_with_retry(
    model_id: str,
    payload: Dict[str, Any],
    *,
    accept: str = "application/json",
    content_type: str = "application/json",
    tries: int = 5,
    base: float = 0.4,
    cap: float = 4.0,
) -> Dict[str, Any]:
    delay = base
    last_err: Optional[Exception] = None
    for attempt in range(1, tries + 1):
        try:
            resp = bedrock.invoke_model(
                modelId=model_id,
                accept=accept,
                contentType=content_type,
                body=json.dumps(payload),
            )
            data_bytes: bytes = resp["body"].read()
            return json.loads(data_bytes.decode("utf-8", errors="replace"))
        except Exception as e:
            last_err = e
            if attempt == tries:
                raise
            time.sleep(delay + random.random() * 0.2)
            delay = min(delay * 2, cap)
    raise RuntimeError(f"Bedrock invoke failed: {last_err}")

def _embed(text: str) -> np.ndarray:
    out = _invoke_json_with_retry(EMBED_MODEL_ID, {"inputText": text})
    emb = out.get("embedding")
    if not isinstance(emb, list) or not emb:
        raise RuntimeError("Bad embedding response (missing 'embedding').")
    v = np.array(emb, dtype=np.float32)
    v /= (np.linalg.norm(v) or 1.0)
    return v.astype(np.float32, copy=False)[None, :]  # shape (1, d)

def _chat(question: str, context: str) -> str:
    payload = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": MAX_TOKENS,
        "messages": [{
            "role": "user",
            "content": [{
                "type": "text",
                "text": (
                    "You are a concise assistant that ONLY uses the provided context. "
                    "If the answer is not in the context, say you don't know.\n\n"
                    f"Question:\n{question}\n\nContext:\n{context}"
                )
            }]
        }],
    }
    data = _invoke_json_with_retry(CHAT_MODEL_ID, payload)
    blocks = data.get("content", [])
    if isinstance(blocks, list):
        for b in blocks:
            if isinstance(b, dict) and b.get("type") == "text":
                t = b.get("text")
                if isinstance(t, str) and t.strip():
                    return t.strip()
    return "I couldn't find the answer in the indexed context."

# -----------------------------
# Index & metadata (freshness on BOTH files)
# -----------------------------
def _ensure_index_loaded() -> None:
    """Download index & meta if either object changed or hasn't been loaded."""
    global INDEX, META, INDEX_ETAG, META_ETAG

    # HEAD both objects (meta may be updated without index changing)
    h_idx = s3.head_object(Bucket=BUCKET, Key=INDEX_PREFIX + "index.faiss")
    h_met = s3.head_object(Bucket=BUCKET, Key=INDEX_PREFIX + "meta.jsonl")
    idx_etag = h_idx["ETag"].strip('"')
    met_etag = h_met["ETag"].strip('"')

    if INDEX is not None and INDEX_ETAG == idx_etag and META_ETAG == met_etag:
        return

    idx_path  = "/tmp/index.faiss"
    meta_path = "/tmp/meta.jsonl"
    s3.download_file(BUCKET, INDEX_PREFIX + "index.faiss", idx_path)
    s3.download_file(BUCKET, INDEX_PREFIX + "meta.jsonl",  meta_path)

    INDEX = faiss.read_index(idx_path)
    META  = [json.loads(line) for line in io.open(meta_path, "r", encoding="utf-8")]

    INDEX_ETAG, META_ETAG = idx_etag, met_etag

# -----------------------------
# Retrieval
# -----------------------------
def _search(index: faiss.Index, q_vec: np.ndarray, k: int, filters: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Vector search + simple metadata filtering (client-side)."""
    k = max(1, min(int(k), len(META)))
    D, I = index.search(q_vec.astype(np.float32, copy=False), k)  # type: ignore[attr-defined]

    results: List[Dict[str, Any]] = []
    for dist, idx in zip(D[0].tolist(), I[0].tolist()):
        if idx == -1:
            continue
        m = META[idx]

        # optional filters
        if filters:
            if "doc_id" in filters:
                allowed = filters["doc_id"]
                if isinstance(allowed, list) and m.get("doc_id") not in allowed:
                    continue
            if "tags" in filters:
                req = set(filters["tags"]) if isinstance(filters["tags"], list) else set()
                have = set(m.get("tags", []))
                if req and not (req & have):
                    continue
            if "mime" in filters:
                allowed_mime = filters["mime"]
                if isinstance(allowed_mime, list) and m.get("mime") not in allowed_mime:
                    continue

        results.append({**m, "distance": float(dist)})
    return results

# -----------------------------
# Context composition helpers
# -----------------------------
def _read_snippet_from_s3_uri(s3_uri: str, byte_limit: int = 2048) -> str:
    """Best-effort tiny read from S3 when preview is missing."""
    try:
        u = urlparse(s3_uri)
        bucket = u.netloc
        key = u.path.lstrip("/")
        obj = s3.get_object(Bucket=bucket, Key=key, Range=f"bytes=0-{byte_limit-1}")
        text = obj["Body"].read().decode("utf-8", "ignore")
        return re.sub(r"\s+", " ", text).strip()[:300]
    except Exception:
        return ""

def _group_hits(hits: List[Dict[str, Any]], max_docs: int) -> List[Dict[str, Any]]:
    """Group chunk hits by document; score by best chunk; keep top docs."""
    bydoc: Dict[str, List[Dict[str, Any]]] = collections.defaultdict(list)
    for h in hits:
        bydoc[h["doc_id"]].append(h)

    scored: List[Dict[str, Any]] = []
    for doc_id, chunks in bydoc.items():
        best = sorted(chunks, key=lambda x: -x["distance"])[:3]
        top = best[0]
        scored.append({
            "doc_id": doc_id,
            "title": top.get("title"),
            "s3_uri": top.get("s3_uri"),
            "chunks": best,
            "score": float(top["distance"]),
        })
    return sorted(scored, key=lambda d: -d["score"])[:max_docs]

def _build_context(grouped_docs: List[Dict[str, Any]], max_chars: int = CTX_CHAR_BUDGET) -> str:
    """Compose a compact, grouped context for the chat model."""
    buf: List[str] = []
    used = 0
    for d in grouped_docs:
        title = d.get("title") or "Untitled"
        s3_uri = d.get("s3_uri") or ""
        header = f"Document: {title} ({s3_uri})"
        if used + len(header) + 2 > max_chars:
            break
        buf.append(header)
        used += len(header) + 2

        for c in d["chunks"]:
            snippet = (c.get("preview") or "").strip()
            if not snippet and s3_uri:
                # Fallback if preview missing/stale
                snippet = _read_snippet_from_s3_uri(s3_uri)
            if not snippet:
                continue
            if used
