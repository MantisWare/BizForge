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
    #[serde(default)]
    fullscreen: bool,
}

const WINDOW_STORE_FILE: &str = "window-state.json";
const WINDOW_STORE_KEY: &str = "main";
const SAVE_DEBOUNCE_MS: u64 = 500;

fn load_window_state(app: &tauri::AppHandle) -> Option<WindowState> {
    let store = app.store(WINDOW_STORE_FILE).ok()?;
    let val = store.get(WINDOW_STORE_KEY)?;
    serde_json::from_value(val).ok()
}

fn save_window_state(app: &tauri::AppHandle, state: &WindowState) {
    if let Ok(store) = app.store(WINDOW_STORE_FILE) {
        if let Ok(val) = serde_json::to_value(state) {
            store.set(WINDOW_STORE_KEY, val);
            let _ = store.save();
        }
    }
}

fn capture_window_state(
    window: &tauri::WebviewWindow,
    previous: Option<&WindowState>,
) -> Option<WindowState> {
    let maximized = window.is_maximized().ok().unwrap_or(false);
    let fullscreen = window.is_fullscreen().ok().unwrap_or(false);

    if maximized || fullscreen {
        return Some(WindowState {
            x: previous.map_or(0.0, |p| p.x),
            y: previous.map_or(0.0, |p| p.y),
            width: previous.map_or(1440.0, |p| p.width),
            height: previous.map_or(900.0, |p| p.height),
            maximized,
            fullscreen,
        });
    }

    let pos = window.outer_position().ok()?;
    let size = window.outer_size().ok()?;
    Some(WindowState {
        x: pos.x as f64,
        y: pos.y as f64,
        width: size.width as f64,
        height: size.height as f64,
        maximized: false,
        fullscreen: false,
    })
}

/// Check whether the saved window position intersects at least one currently
/// connected monitor. Returns `true` if the window would be visible.
fn is_position_on_screen(window: &tauri::WebviewWindow, state: &WindowState) -> bool {
    let monitors = match window.available_monitors() {
        Ok(m) => m,
        Err(_) => return true,
    };

    if monitors.is_empty() {
        return true;
    }

    let win_left = state.x as i32;
    let win_top = state.y as i32;
    let win_right = win_left + state.width as i32;
    let win_bottom = win_top + state.height as i32;

    for monitor in &monitors {
        let mx = monitor.position().x;
        let my = monitor.position().y;
        let mw = monitor.size().width as i32;
        let mh = monitor.size().height as i32;

        let overlap_x = (win_right.min(mx + mw) - win_left.max(mx)).max(0);
        let overlap_y = (win_bottom.min(my + mh) - win_top.max(my)).max(0);

        if overlap_x >= 100 && overlap_y >= 50 {
            return true;
        }
    }

    false
}

fn restore_window_state(window: &tauri::WebviewWindow, state: &WindowState) {
    use tauri::{PhysicalPosition, PhysicalSize};

    // Restore size first (needed before position to check screen bounds correctly)
    let w = (state.width as u32).max(960);
    let h = (state.height as u32).max(600);
    let _ = window.set_size(PhysicalSize::new(w, h));

    if is_position_on_screen(window, state) {
        let _ = window.set_position(PhysicalPosition::new(state.x as i32, state.y as i32));
    }

    if state.fullscreen {
        let _ = window.set_fullscreen(true);
    } else if state.maximized {
        let _ = window.maximize();
    } else {
        let _ = window.unmaximize();
        let _ = window.set_fullscreen(false);
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

/// In dev mode, webviews load from the Vite dev server (`devUrl`). If the
/// Rust binary starts before Vite is listening, WKWebView (macOS) renders a
/// blank page and never retries automatically. This spawns a background thread
/// that polls the dev server address and reloads all webviews once it becomes
/// reachable — fixing the blank-window-on-restart problem.
#[cfg(debug_assertions)]
fn ensure_dev_server_ready(app: &tauri::AppHandle) {
    use std::net::{SocketAddr, TcpStream};
    use std::time::{Duration, Instant};

    let addr: SocketAddr = "127.0.0.1:5200".parse().unwrap();
    let handle = app.clone();

    std::thread::spawn(move || {
        let start = Instant::now();
        let timeout = Duration::from_secs(60);
        let poll_interval = Duration::from_millis(400);
        let mut needed_retry = false;

        loop {
            if start.elapsed() > timeout {
                eprintln!(
                    "[bizforge] Dev server at {} not reachable after {:.0}s — giving up",
                    addr,
                    timeout.as_secs_f64()
                );
                return;
            }

            match TcpStream::connect_timeout(&addr.into(), Duration::from_secs(1)) {
                Ok(_) => break,
                Err(_) => {
                    needed_retry = true;
                    std::thread::sleep(poll_interval);
                }
            }
        }

        if needed_retry {
            // Vite's TCP listener is up but it may still be compiling / optimizing
            // dependencies. A brief pause avoids reloading into a half-ready state.
            std::thread::sleep(Duration::from_millis(1200));
            reload_all_webviews(&handle);
            eprintln!(
                "[bizforge] Dev server ready after {:.1}s — reloaded webviews",
                start.elapsed().as_secs_f64()
            );
        }
    });
}

/// Force-reload every known webview so blank pages caused by a premature load
/// (before the dev server was listening) get a second chance to render.
#[cfg(debug_assertions)]
fn reload_all_webviews(app: &tauri::AppHandle) {
    for label in &["splash", "main"] {
        if let Some(win) = app.get_webview_window(label) {
            let _ = win.eval("location.reload()");
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(main) = app.get_webview_window("main") {
                let _ = main.show();
                let _ = main.unminimize();
                let _ = main.set_focus();
            }
        }))
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
            filesystem::scaffold_project_dir,
            filesystem::write_project_file,
            filesystem::check_workspace_health,
            filesystem::repair_workspace,
            filesystem::detect_adapters,
            filesystem::install_adapter,
            filesystem::setup_osa,
            filesystem::stop_osa,
            filesystem::get_system_resources,
            filesystem::remove_dir_recursive,
            filesystem::read_log_files,
            filesystem::copy_working_directory,
            mcp::mcp_status,
            mcp::mcp_client_config,
            mcp::mcp_build,
        ])
        .setup(|app| {
            // In dev mode, ensure the Vite dev server is reachable before
            // webviews try to render. If it wasn't ready at initial load,
            // this will reload them once it comes up.
            #[cfg(debug_assertions)]
            ensure_dev_server_ready(app.handle());

            // Restore saved window position/size before the window becomes visible
            if let Some(main) = app.get_webview_window("main") {
                if let Some(state) = load_window_state(&app.handle().clone()) {
                    restore_window_state(&main, &state);
                }

                // Listen for move, resize, and close events to persist window state.
                // Debounce rapid move/resize events using a timestamp check to
                // avoid excessive disk writes during drag. CloseRequested always
                // saves immediately.
                let app_handle = app.handle().clone();
                let last_state = std::sync::Mutex::new(
                    load_window_state(&app_handle),
                );
                let pending_state: std::sync::Arc<std::sync::Mutex<Option<WindowState>>> =
                    std::sync::Arc::new(std::sync::Mutex::new(None));
                let debounce_scheduled: std::sync::Arc<std::sync::atomic::AtomicBool> =
                    std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));

                main.on_window_event(move |event| {
                    use tauri::WindowEvent;
                    match event {
                        WindowEvent::Moved(_) | WindowEvent::Resized(_) => {
                            if let Some(win) = app_handle.get_webview_window("main") {
                                if win.is_visible().unwrap_or(false) {
                                    let prev = last_state.lock().ok().and_then(|g| g.clone());
                                    if let Some(state) = capture_window_state(&win, prev.as_ref()) {
                                        if let Ok(mut guard) = last_state.lock() {
                                            *guard = Some(state.clone());
                                        }
                                        if let Ok(mut ps) = pending_state.lock() {
                                            *ps = Some(state);
                                        }
                                        // Spawn a debounce thread if one isn't already waiting
                                        if !debounce_scheduled.swap(true, std::sync::atomic::Ordering::SeqCst) {
                                            let ps = pending_state.clone();
                                            let flag = debounce_scheduled.clone();
                                            let handle = app_handle.clone();
                                            std::thread::spawn(move || {
                                                std::thread::sleep(std::time::Duration::from_millis(SAVE_DEBOUNCE_MS));
                                                flag.store(false, std::sync::atomic::Ordering::SeqCst);
                                                if let Some(state) = ps.lock().ok().and_then(|mut g| g.take()) {
                                                    save_window_state(&handle, &state);
                                                }
                                            });
                                        }
                                    }
                                }
                            }
                        }
                        WindowEvent::CloseRequested { .. } => {
                            // Flush any pending state immediately
                            let final_state = pending_state.lock().ok().and_then(|mut g| g.take());
                            if let Some(state) = final_state {
                                save_window_state(&app_handle, &state);
                            } else if let Some(win) = app_handle.get_webview_window("main") {
                                let prev = last_state.lock().ok().and_then(|g| g.clone());
                                if let Some(state) = capture_window_state(&win, prev.as_ref()) {
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
