function injectHeader(activePage) {
  const COGNITO_DOMAIN = "$${COGNITO_DOMAIN}";
  const CLIENT_ID = "$${CLIENT_ID}";
  const REDIRECT_URI = "$${REDIRECT_URI}";

  const container = document.createElement("nav");
  container.style = "margin-bottom: 2em; font-family: sans-serif;";
  container.innerHTML = `
    <a href="upload.html" style="margin-right: 1em; ${activePage === "upload" ? "font-weight: bold;" : ""}">Upload</a>
    <a href="list.html" style="margin-right: 1em; ${activePage === "list" ? "font-weight: bold;" : ""}">Downloads</a>
    <button id="logoutBtn" style="margin-left: 2em;">Logout</button>
    <hr style="margin-top: 1em;" />
  `;
  document.body.insertBefore(container, document.body.firstChild);

  document.getElementById("logoutBtn").onclick = function () {
    localStorage.removeItem("id_token");
    localStorage.removeItem("access_token");
    window.location.href = `${COGNITO_DOMAIN}/logout?client_id=${CLIENT_ID}&logout_uri=${REDIRECT_URI}`;
  };
}
