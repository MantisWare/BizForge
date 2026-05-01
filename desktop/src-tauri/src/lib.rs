mod filesystem;
mod mcp;

use serde::{Deserialize, Serialize};
use tauri::Manager;
use tauri::WebviewWindowBuilder;
use tauri::WebviewUrl;
use tauri_plugin_store::StoreExt;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WindowState {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    maximized: bool,
}

const WINDOW_STORE_FILE: &str = "window-state.json";
const WINDOW_STORE_KEY: &str = "main";

fn load_window_state(app: &tauri::AppHandle) -> Option<WindowState> {
    let store = app.store(WINDOW_STORE_FILE).ok()?;
    let val = store.get(WINDOW_STORE_KEY)?;
    serde_json::from_value(val).ok()
}

fn save_window_state(app: &tauri::AppHandle, state: &WindowState) {
    if let Ok(store) = app.store(WINDOW_STORE_FILE) {
        if let Ok(val) = serde_json::to_value(state) {
            store.set(WINDOW_STORE_KEY, val);
        }
    }
}

fn capture_window_state(window: &tauri::WebviewWindow) -> Option<WindowState> {
    let pos = window.outer_position().ok()?;
    let size = window.outer_size().ok()?;
    let maximized = window.is_maximized().ok().unwrap_or(false);
    Some(WindowState {
        x: pos.x as f64,
        y: pos.y as f64,
        width: size.width as f64,
        height: size.height as f64,
        maximized,
    })
}

fn restore_window_state(window: &tauri::WebviewWindow, state: &WindowState) {
    use tauri::{PhysicalPosition, PhysicalSize};
    let _ = window.set_position(PhysicalPosition::new(state.x as i32, state.y as i32));
    let _ = window.set_size(PhysicalSize::new(state.width as u32, state.height as u32));
    if state.maximized {
        let _ = window.maximize();
    }
}

#[tauri::command]
fn close_splash(app: tauri::AppHandle) {
    if let Some(splash) = app.get_webview_window("splash") {
        let _ = splash.close();
    }
    if let Some(main) = app.get_webview_window("main") {
        let _ = main.show();
        let _ = main.set_focus();
    }
}

#[tauri::command]
fn open_monitor(app: tauri::AppHandle, workspace_id: String) -> Result<(), String> {
    let label = format!("monitor-{}", workspace_id.replace(|c: char| !c.is_alphanumeric() && c != '-', "_"));

    if let Some(existing) = app.get_webview_window(&label) {
        let _ = existing.show();
        let _ = existing.set_focus();
        return Ok(());
    }

    let url_path = format!("/monitor?workspace={}", workspace_id);

    WebviewWindowBuilder::new(
        &app,
        &label,
        WebviewUrl::App(url_path.into()),
    )
    .title(format!("Bizforge Monitor — {}", workspace_id))
    .inner_size(1200.0, 800.0)
    .min_inner_size(800.0, 600.0)
    .decorations(true)
    .resizable(true)
    .build()
    .map_err(|e| e.to_string())?;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            close_splash,
            open_monitor,
            filesystem::scan_bizforge_dir,
            filesystem::list_bizforge_agents,
            filesystem::list_bizforge_projects,
            filesystem::list_bizforge_schedules,
            filesystem::watch_bizforge_dir,
            filesystem::scaffold_bizforge_dir,
            filesystem::detect_adapters,
            filesystem::install_adapter,
            filesystem::setup_osa,
            mcp::mcp_status,
            mcp::mcp_client_config,
            mcp::mcp_build,
        ])
        .setup(|app| {
            // Restore saved window position/size before the window becomes visible
            if let Some(main) = app.get_webview_window("main") {
                if let Some(state) = load_window_state(&app.handle().clone()) {
                    restore_window_state(&main, &state);
                }

                // Listen for move, resize, and close events to persist window state
                let app_handle = app.handle().clone();
                main.on_window_event(move |event| {
                    use tauri::WindowEvent;
                    match event {
                        WindowEvent::Moved(_) | WindowEvent::Resized(_) => {
                            if let Some(win) = app_handle.get_webview_window("main") {
                                if win.is_visible().unwrap_or(false) {
                                    if let Some(state) = capture_window_state(&win) {
                                        save_window_state(&app_handle, &state);
                                    }
                                }
                            }
                        }
                        WindowEvent::CloseRequested { .. } => {
                            if let Some(win) = app_handle.get_webview_window("main") {
                                if let Some(state) = capture_window_state(&win) {
                                    save_window_state(&app_handle, &state);
                                }
                            }
                        }
                        _ => {}
                    }
                });
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
