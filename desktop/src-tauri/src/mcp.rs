use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpStatus {
    pub ready: bool,
    pub server_path: String,
    pub server_exists: bool,
}

fn resolve_mcp_server_path() -> PathBuf {
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()));

    let candidates = [
        // Production: alongside the Tauri binary
        exe_dir
            .as_ref()
            .map(|d| d.join("mcp-server").join("dist").join("index.js")),
        // Development: relative to the workspace root
        Some(
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("..")
                .join("mcp-server")
                .join("dist")
                .join("index.js"),
        ),
    ];

    for candidate in candidates.into_iter().flatten() {
        if candidate.exists() {
            return candidate;
        }
    }

    // Fallback — return the dev path even if it doesn't exist yet
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("mcp-server")
        .join("dist")
        .join("index.js")
}

/// Check whether the MCP server JS bundle exists and is ready for clients.
#[tauri::command]
pub fn mcp_status() -> McpStatus {
    let server_path = resolve_mcp_server_path();
    let server_exists = server_path.exists();
    McpStatus {
        ready: server_exists,
        server_path: server_path.to_string_lossy().to_string(),
        server_exists,
    }
}

/// Generate the MCP configuration JSON that external clients (Claude Desktop,
/// Cursor, etc.) need to add to their MCP settings.
#[tauri::command]
pub fn mcp_client_config() -> serde_json::Value {
    let server_path = resolve_mcp_server_path();
    serde_json::json!({
        "mcpServers": {
            "bizforge": {
                "command": "node",
                "args": [server_path.to_string_lossy()],
                "env": {
                    "BIZFORGE_API_URL": "http://127.0.0.1:9089"
                }
            }
        }
    })
}

/// Build the MCP server from source (runs `npm run build` in mcp-server/).
#[tauri::command]
pub async fn mcp_build() -> Result<McpStatus, String> {
    let mcp_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("mcp-server");

    if !mcp_dir.join("node_modules").exists() {
        let install = std::process::Command::new("npm")
            .arg("install")
            .current_dir(&mcp_dir)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .output()
            .map_err(|e| format!("Failed to run npm install: {e}"))?;

        if !install.status.success() {
            let stderr = String::from_utf8_lossy(&install.stderr);
            return Err(format!("npm install failed: {stderr}"));
        }
    }

    let build = std::process::Command::new("npm")
        .arg("run")
        .arg("build")
        .current_dir(&mcp_dir)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .output()
        .map_err(|e| format!("Failed to run npm run build: {e}"))?;

    if !build.status.success() {
        let stderr = String::from_utf8_lossy(&build.stderr);
        return Err(format!("MCP server build failed: {stderr}"));
    }

    Ok(mcp_status())
}
