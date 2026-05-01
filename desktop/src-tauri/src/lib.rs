mod filesystem;

use tauri::Manager;
use tauri::WebviewWindowBuilder;
use tauri::WebviewUrl;

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
        ])
        .setup(|_app| {
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
