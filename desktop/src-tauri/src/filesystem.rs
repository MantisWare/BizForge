use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

fn expand_tilde(path: &str) -> PathBuf {
    if path.starts_with("~/") || path == "~" {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join(path.strip_prefix("~/").unwrap_or(""));
        }
    }
    PathBuf::from(path)
}

// ── Types ────────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BizforgeWorkspace {
    pub path: String,
    pub name: String,
    pub agents: Vec<BizforgeAgentDef>,
    pub projects: Vec<BizforgeProjectDef>,
    pub schedules: Vec<BizforgeScheduleDef>,
    pub skills: Vec<BizforgeSkillDef>,
    /// Raw contents of .bizforge/SYSTEM.md (if present)
    pub system_md: Option<String>,
    /// Raw contents of .bizforge/COMPANY.md (if present)
    pub company_md: Option<String>,
    pub scanned_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BizforgeAgentDef {
    pub id: String,
    pub name: String,
    pub emoji: Option<String>,
    pub role: String,
    pub adapter: String,
    pub model: Option<String>,
    pub system_prompt: Option<String>,
    pub skills: Vec<String>,
    pub schedule: Option<String>,
    pub file_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BizforgeProjectDef {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub path: String,
    pub agents: Vec<String>,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BizforgeScheduleDef {
    pub id: String,
    pub agent_id: String,
    pub cron: String,
    pub description: Option<String>,
    pub enabled: bool,
    pub context: Option<String>,
    pub file_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BizforgeSkillDef {
    pub id: String,
    pub name: String,
    pub description: String,
    pub category: String,
    pub version: Option<String>,
    pub file_path: String,
}

// ── IPC Commands ─────────────────────────────────────────────────────────────

/// Scan a .bizforge/ directory and return the full workspace definition.
/// If the directory doesn't exist, auto-creates the required structure.
#[tauri::command]
pub async fn scan_bizforge_dir(path: String) -> Result<BizforgeWorkspace, String> {
    let bizforge_path = expand_tilde(&path);
    if !bizforge_path.exists() {
        // Auto-create the .bizforge directory structure
        std::fs::create_dir_all(&bizforge_path)
            .map_err(|e| format!("Failed to create .bizforge directory at {}: {}", path, e))?;
        for dir in REQUIRED_DIRS {
            std::fs::create_dir_all(bizforge_path.join(dir))
                .map_err(|e| format!("Failed to create {}: {}", dir, e))?;
        }
    }

    let name = bizforge_path
        .parent()
        .and_then(|p| p.file_name())
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "Unknown".to_string());

    // Ensure SYSTEM.md exists — create with defaults if missing
    let system_md_path = bizforge_path.join("SYSTEM.md");
    if !system_md_path.exists() {
        let default_system = format!(
            "---\nname: {}\ndescription: A Bizforge workspace\ncreated_at: {}\n---\n\n# {}\n\nA Bizforge workspace.\n",
            name, chrono_now(), name
        );
        let _ = std::fs::write(&system_md_path, &default_system);
    }

    // Read optional top-level markdown files
    let system_md = std::fs::read_to_string(&system_md_path).ok();
    let company_md = std::fs::read_to_string(bizforge_path.join("COMPANY.md")).ok();

    // Prefer the name from SYSTEM.md frontmatter over the directory name
    let name = system_md
        .as_deref()
        .and_then(|s| parse_frontmatter_name(s))
        .unwrap_or(name);

    let agents = list_agents_internal(&bizforge_path)?;
    let projects = list_projects_internal(&bizforge_path)?;
    let schedules = list_schedules_internal(&bizforge_path)?;
    let skills = list_skills_internal(&bizforge_path)?;

    Ok(BizforgeWorkspace {
        path,
        name,
        agents,
        projects,
        schedules,
        skills,
        system_md,
        company_md,
        scanned_at: chrono_now(),
    })
}

/// List all agent definitions from .bizforge/agents/*.md
#[tauri::command]
pub async fn list_bizforge_agents(path: String) -> Result<Vec<BizforgeAgentDef>, String> {
    let bizforge_path = expand_tilde(&path);
    list_agents_internal(&bizforge_path)
}

/// List all projects from .bizforge/projects/*/
#[tauri::command]
pub async fn list_bizforge_projects(path: String) -> Result<Vec<BizforgeProjectDef>, String> {
    let bizforge_path = expand_tilde(&path);
    list_projects_internal(&bizforge_path)
}

/// List all schedules from .bizforge/schedules/*.yaml
#[tauri::command]
pub async fn list_bizforge_schedules(path: String) -> Result<Vec<BizforgeScheduleDef>, String> {
    let bizforge_path = expand_tilde(&path);
    list_schedules_internal(&bizforge_path)
}

/// Watch a .bizforge/ directory for changes (returns immediately, sends events via Tauri events)
#[tauri::command]
pub async fn watch_bizforge_dir(
    app: tauri::AppHandle,
    path: String,
) -> Result<(), String> {
    use notify::{Config, Event, RecommendedWatcher, RecursiveMode, Watcher};
    use std::sync::mpsc::channel;
    use tauri::Emitter;

    let (tx, rx) = channel::<notify::Result<Event>>();

    let mut watcher = RecommendedWatcher::new(tx, Config::default())
        .map_err(|e| format!("Failed to create watcher: {}", e))?;

    let resolved_path = expand_tilde(&path);
    watcher
        .watch(&resolved_path, RecursiveMode::Recursive)
        .map_err(|e| format!("Failed to watch directory: {}", e))?;

    // Spawn a thread to forward filesystem events to the frontend
    let _handle = std::thread::spawn(move || {
        let _watcher = watcher; // Keep watcher alive
        for result in rx {
            if let Ok(event) = result {
                let paths: Vec<String> = event
                    .paths
                    .iter()
                    .map(|p| p.to_string_lossy().to_string())
                    .collect();
                let kind = match event.kind {
                    notify::EventKind::Create(_) => "create",
                    notify::EventKind::Modify(_) => "modify",
                    notify::EventKind::Remove(_) => "remove",
                    _ => continue,
                };
                let _ = app.emit(
                    "bizforge-fs-event",
                    serde_json::json!({
                        "kind": kind,
                        "paths": paths,
                        "timestamp": chrono_now(),
                    }),
                );
            }
        }
    });

    Ok(())
}

/// Agent template for scaffolding
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentTemplate {
    pub id: String,
    pub name: String,
    pub emoji: String,
    pub role: String,
    pub adapter: String,
    pub model: Option<String>,
    pub skills: Vec<String>,
    pub system_prompt: Option<String>,
}

/// Create a new .bizforge/ workspace directory with full structure
#[tauri::command]
pub async fn scaffold_bizforge_dir(
    path: String,
    name: String,
    description: Option<String>,
    agents: Vec<AgentTemplate>,
) -> Result<BizforgeWorkspace, String> {
    let base = expand_tilde(&path);
    let bizforge_dir = base.join(".bizforge");

    // Create directory structure
    let dirs = ["agents", "skills", "projects", "schedules", "reference"];
    for dir in &dirs {
        std::fs::create_dir_all(bizforge_dir.join(dir))
            .map_err(|e| format!("Failed to create {}: {}", dir, e))?;
    }

    // Write SYSTEM.md
    let desc_line = description.as_deref().unwrap_or("A Bizforge workspace");
    let system_md = format!(
        "---\nname: {}\ndescription: {}\ncreated_at: {}\n---\n\n# {}\n\n{}\n",
        name, desc_line, chrono_now(), name, desc_line
    );
    std::fs::write(bizforge_dir.join("SYSTEM.md"), &system_md)
        .map_err(|e| format!("Failed to write SYSTEM.md: {}", e))?;

    // Write COMPANY.md
    let company_md = "---\nname: My Organization\n---\n\n# Organization\n\nConfigure your organization details here.\n";
    std::fs::write(bizforge_dir.join("COMPANY.md"), company_md)
        .map_err(|e| format!("Failed to write COMPANY.md: {}", e))?;

    // Write agent files
    for agent in &agents {
        let skills_yaml = agent.skills.iter()
            .map(|s| format!("  - {}", s))
            .collect::<Vec<_>>()
            .join("\n");

        let prompt_block = agent.system_prompt.as_ref()
            .filter(|s| !s.is_empty())
            .map(|s| format!("system_prompt: |\n  {}\n", s.replace('\n', "\n  ")))
            .unwrap_or_default();

        let model_line = agent.model.as_ref()
            .map(|m| format!("model: {}\n", m))
            .unwrap_or_default();

        let agent_md = format!(
            "---\nname: {}\nemoji: {}\nrole: {}\nadapter: {}\n{}{}skills:\n{}\n---\n\n# {}\n\n{}\n",
            agent.name, agent.emoji, agent.role, agent.adapter,
            model_line, prompt_block, skills_yaml,
            agent.name,
            agent.system_prompt.as_deref().unwrap_or("Agent configuration.")
        );

        let agent_path = bizforge_dir.join("agents").join(format!("{}.md", agent.id));
        std::fs::write(&agent_path, &agent_md)
            .map_err(|e| format!("Failed to write agent {}: {}", agent.id, e))?;
    }

    // Scan and return the workspace
    scan_bizforge_dir(bizforge_dir.to_string_lossy().to_string()).await
}

// ── Internal Helpers ─────────────────────────────────────────────────────────

fn list_agents_internal(bizforge_path: &Path) -> Result<Vec<BizforgeAgentDef>, String> {
    let agents_dir = bizforge_path.join("agents");
    if !agents_dir.exists() {
        return Ok(vec![]);
    }

    let mut agents = Vec::new();
    for entry in WalkDir::new(&agents_dir).max_depth(1).into_iter().flatten() {
        let path = entry.path();
        if path.extension().map_or(false, |ext| ext == "md" || ext == "yaml" || ext == "yml") {
            if let Ok(content) = std::fs::read_to_string(path) {
                if let Some(agent) = parse_agent_frontmatter(&content, path) {
                    agents.push(agent);
                }
            }
        }
    }
    Ok(agents)
}

fn list_projects_internal(bizforge_path: &Path) -> Result<Vec<BizforgeProjectDef>, String> {
    let projects_dir = bizforge_path.join("projects");
    if !projects_dir.exists() {
        return Ok(vec![]);
    }

    let mut projects = Vec::new();
    for entry in std::fs::read_dir(&projects_dir).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();
        if path.is_dir() {
            let id = path
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();

            // Try to read project.yaml for metadata
            let meta_path = path.join("project.yaml");
            let (name, description, agent_ids, tags) = if meta_path.exists() {
                if let Ok(content) = std::fs::read_to_string(&meta_path) {
                    parse_project_yaml(&content, &id)
                } else {
                    (id.clone(), None, vec![], vec![])
                }
            } else {
                (id.clone(), None, vec![], vec![])
            };

            projects.push(BizforgeProjectDef {
                id: id.clone(),
                name,
                description,
                path: path.to_string_lossy().to_string(),
                agents: agent_ids,
                tags,
            });
        }
    }
    Ok(projects)
}

fn list_schedules_internal(bizforge_path: &Path) -> Result<Vec<BizforgeScheduleDef>, String> {
    let schedules_dir = bizforge_path.join("schedules");
    if !schedules_dir.exists() {
        return Ok(vec![]);
    }

    let mut schedules = Vec::new();
    for entry in WalkDir::new(&schedules_dir).max_depth(1).into_iter().flatten() {
        let path = entry.path();
        if path.extension().map_or(false, |ext| ext == "yaml" || ext == "yml") {
            if let Ok(content) = std::fs::read_to_string(path) {
                if let Some(schedule) = parse_schedule_yaml(&content, path) {
                    schedules.push(schedule);
                }
            }
        }
    }
    Ok(schedules)
}

fn list_skills_internal(bizforge_path: &Path) -> Result<Vec<BizforgeSkillDef>, String> {
    let skills_dir = bizforge_path.join("skills");
    if !skills_dir.exists() {
        return Ok(vec![]);
    }

    let mut skills = Vec::new();
    for entry in WalkDir::new(&skills_dir).max_depth(2).into_iter().flatten() {
        let path = entry.path();
        if path.extension().map_or(false, |ext| ext == "md" || ext == "yaml" || ext == "yml") {
            if let Ok(content) = std::fs::read_to_string(path) {
                if let Some(skill) = parse_skill_frontmatter(&content, path) {
                    skills.push(skill);
                }
            }
        }
    }
    Ok(skills)
}

/// Extract the `name` field from YAML frontmatter of a markdown file
fn parse_frontmatter_name(content: &str) -> Option<String> {
    let trimmed = content.trim();
    if !trimmed.starts_with("---") {
        return None;
    }
    let after_first = &trimmed[3..];
    let end = after_first.find("---")?;
    let yaml_str = &after_first[..end];
    let yaml: serde_yaml::Value = serde_yaml::from_str(yaml_str).ok()?;
    let map = yaml.as_mapping()?;
    get_str(map, "name")
}

/// Parse YAML frontmatter from a markdown agent definition file
fn parse_agent_frontmatter(content: &str, path: &Path) -> Option<BizforgeAgentDef> {
    // Extract YAML between --- markers
    let trimmed = content.trim();
    if !trimmed.starts_with("---") {
        return None;
    }
    let after_first = &trimmed[3..];
    let end = after_first.find("---")?;
    let yaml_str = &after_first[..end];

    let yaml: serde_yaml::Value = serde_yaml::from_str(yaml_str).ok()?;
    let map = yaml.as_mapping()?;

    let id = path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();

    Some(BizforgeAgentDef {
        id,
        name: get_str(map, "name").unwrap_or_else(|| "Unknown".to_string()),
        emoji: get_str(map, "emoji"),
        role: get_str(map, "role").unwrap_or_default(),
        adapter: get_str(map, "adapter").unwrap_or_else(|| "osa".to_string()),
        model: get_str(map, "model"),
        system_prompt: get_str(map, "system_prompt"),
        skills: get_str_list(map, "skills"),
        schedule: get_str(map, "schedule"),
        file_path: path.to_string_lossy().to_string(),
    })
}

fn parse_skill_frontmatter(content: &str, path: &Path) -> Option<BizforgeSkillDef> {
    let trimmed = content.trim();
    if !trimmed.starts_with("---") {
        return None;
    }
    let after_first = &trimmed[3..];
    let end = after_first.find("---")?;
    let yaml_str = &after_first[..end];

    let yaml: serde_yaml::Value = serde_yaml::from_str(yaml_str).ok()?;
    let map = yaml.as_mapping()?;

    let id = path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();

    Some(BizforgeSkillDef {
        id,
        name: get_str(map, "name").unwrap_or_else(|| "Unknown".to_string()),
        description: get_str(map, "description").unwrap_or_default(),
        category: get_str(map, "category").unwrap_or_else(|| "general".to_string()),
        version: get_str(map, "version"),
        file_path: path.to_string_lossy().to_string(),
    })
}

fn parse_project_yaml(
    content: &str,
    fallback_name: &str,
) -> (String, Option<String>, Vec<String>, Vec<String>) {
    if let Ok(yaml) = serde_yaml::from_str::<serde_yaml::Value>(content) {
        if let Some(map) = yaml.as_mapping() {
            let name = get_str(map, "name").unwrap_or_else(|| fallback_name.to_string());
            let description = get_str(map, "description");
            let agents = get_str_list(map, "agents");
            let tags = get_str_list(map, "tags");
            return (name, description, agents, tags);
        }
    }
    (fallback_name.to_string(), None, vec![], vec![])
}

fn parse_schedule_yaml(content: &str, path: &Path) -> Option<BizforgeScheduleDef> {
    let yaml: serde_yaml::Value = serde_yaml::from_str(content).ok()?;
    let map = yaml.as_mapping()?;

    let id = path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();

    Some(BizforgeScheduleDef {
        id,
        agent_id: get_str(map, "agent_id").unwrap_or_default(),
        cron: get_str(map, "cron").unwrap_or_default(),
        description: get_str(map, "description"),
        enabled: map
            .get(&serde_yaml::Value::String("enabled".to_string()))
            .and_then(|v| v.as_bool())
            .unwrap_or(true),
        context: get_str(map, "context"),
        file_path: path.to_string_lossy().to_string(),
    })
}

// ── YAML Helpers ─────────────────────────────────────────────────────────────

fn get_str(map: &serde_yaml::Mapping, key: &str) -> Option<String> {
    map.get(&serde_yaml::Value::String(key.to_string()))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

fn get_str_list(map: &serde_yaml::Mapping, key: &str) -> Vec<String> {
    map.get(&serde_yaml::Value::String(key.to_string()))
        .and_then(|v| v.as_sequence())
        .map(|seq| {
            seq.iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default()
}

fn chrono_now() -> String {
    // Simple ISO 8601 without chrono dependency
    use std::time::{SystemTime, UNIX_EPOCH};
    let dur = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    format!("{}Z", dur.as_secs())
}

// ── Workspace Health ─────────────────────────────────────────────────────────

const REQUIRED_DIRS: &[&str] = &["agents", "skills", "projects", "schedules", "reference"];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthIssue {
    pub severity: String,
    pub code: String,
    pub message: String,
    pub path: String,
    pub repairable: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceHealthReport {
    pub healthy: bool,
    pub issues: Vec<HealthIssue>,
    pub checked_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepairResult {
    pub repaired: Vec<String>,
    pub failed: Vec<String>,
    pub health_after: WorkspaceHealthReport,
}

/// Check workspace health: validate directory structure, required files, and content integrity
#[tauri::command]
pub async fn check_workspace_health(path: String) -> Result<WorkspaceHealthReport, String> {
    let workspace_root = expand_tilde(&path);
    let bizforge_dir = if workspace_root.ends_with(".bizforge") {
        workspace_root.clone()
    } else {
        workspace_root.join(".bizforge")
    };

    let mut issues = Vec::new();

    // 1. .bizforge/ root exists
    if !bizforge_dir.exists() {
        issues.push(HealthIssue {
            severity: "error".to_string(),
            code: "missing_root".to_string(),
            message: ".bizforge directory does not exist".to_string(),
            path: bizforge_dir.to_string_lossy().to_string(),
            repairable: true,
        });
        return Ok(WorkspaceHealthReport {
            healthy: false,
            issues,
            checked_at: chrono_now(),
        });
    }

    if !bizforge_dir.is_dir() {
        issues.push(HealthIssue {
            severity: "error".to_string(),
            code: "root_not_dir".to_string(),
            message: ".bizforge exists but is not a directory".to_string(),
            path: bizforge_dir.to_string_lossy().to_string(),
            repairable: false,
        });
        return Ok(WorkspaceHealthReport {
            healthy: false,
            issues,
            checked_at: chrono_now(),
        });
    }

    // 2. Required subdirectories
    for dir_name in REQUIRED_DIRS {
        let dir_path = bizforge_dir.join(dir_name);
        if !dir_path.exists() {
            issues.push(HealthIssue {
                severity: "error".to_string(),
                code: "missing_dir".to_string(),
                message: format!("Required directory '{}' is missing", dir_name),
                path: dir_path.to_string_lossy().to_string(),
                repairable: true,
            });
        } else if !dir_path.is_dir() {
            issues.push(HealthIssue {
                severity: "error".to_string(),
                code: "not_a_dir".to_string(),
                message: format!("'{}' exists but is not a directory", dir_name),
                path: dir_path.to_string_lossy().to_string(),
                repairable: false,
            });
        }
    }

    // 3. SYSTEM.md
    let system_md_path = bizforge_dir.join("SYSTEM.md");
    if !system_md_path.exists() {
        issues.push(HealthIssue {
            severity: "error".to_string(),
            code: "missing_file".to_string(),
            message: "SYSTEM.md is missing (workspace identity file)".to_string(),
            path: system_md_path.to_string_lossy().to_string(),
            repairable: true,
        });
    } else if let Ok(content) = std::fs::read_to_string(&system_md_path) {
        if content.trim().is_empty() {
            issues.push(HealthIssue {
                severity: "warning".to_string(),
                code: "empty_file".to_string(),
                message: "SYSTEM.md is empty".to_string(),
                path: system_md_path.to_string_lossy().to_string(),
                repairable: true,
            });
        } else if parse_frontmatter_name(&content).is_none() {
            issues.push(HealthIssue {
                severity: "warning".to_string(),
                code: "corrupt_frontmatter".to_string(),
                message: "SYSTEM.md has missing or invalid YAML frontmatter (no 'name' field)".to_string(),
                path: system_md_path.to_string_lossy().to_string(),
                repairable: true,
            });
        }
    } else {
        issues.push(HealthIssue {
            severity: "warning".to_string(),
            code: "unreadable_file".to_string(),
            message: "SYSTEM.md exists but cannot be read".to_string(),
            path: system_md_path.to_string_lossy().to_string(),
            repairable: false,
        });
    }

    // 4. COMPANY.md
    let company_md_path = bizforge_dir.join("COMPANY.md");
    if !company_md_path.exists() {
        issues.push(HealthIssue {
            severity: "warning".to_string(),
            code: "missing_file".to_string(),
            message: "COMPANY.md is missing (organization config file)".to_string(),
            path: company_md_path.to_string_lossy().to_string(),
            repairable: true,
        });
    }

    // 5. Validate agent files
    let agents_dir = bizforge_dir.join("agents");
    if agents_dir.is_dir() {
        let mut agent_count = 0u32;
        for entry in WalkDir::new(&agents_dir).max_depth(1).into_iter().flatten() {
            let entry_path = entry.path();
            if entry_path.extension().map_or(false, |ext| ext == "md" || ext == "yaml" || ext == "yml") {
                agent_count += 1;
                if let Ok(content) = std::fs::read_to_string(entry_path) {
                    if content.trim().is_empty() {
                        issues.push(HealthIssue {
                            severity: "warning".to_string(),
                            code: "empty_file".to_string(),
                            message: format!("Agent file '{}' is empty", entry_path.file_name().unwrap_or_default().to_string_lossy()),
                            path: entry_path.to_string_lossy().to_string(),
                            repairable: false,
                        });
                    } else if parse_agent_frontmatter(&content, entry_path).is_none() {
                        issues.push(HealthIssue {
                            severity: "warning".to_string(),
                            code: "corrupt_frontmatter".to_string(),
                            message: format!("Agent file '{}' has invalid or missing YAML frontmatter", entry_path.file_name().unwrap_or_default().to_string_lossy()),
                            path: entry_path.to_string_lossy().to_string(),
                            repairable: false,
                        });
                    }
                }
            }
        }
        if agent_count == 0 {
            issues.push(HealthIssue {
                severity: "info".to_string(),
                code: "empty_dir".to_string(),
                message: "No agent definitions found in agents/ directory".to_string(),
                path: agents_dir.to_string_lossy().to_string(),
                repairable: false,
            });
        }
    }

    // 6. Validate schedule files
    let schedules_dir = bizforge_dir.join("schedules");
    if schedules_dir.is_dir() {
        for entry in WalkDir::new(&schedules_dir).max_depth(1).into_iter().flatten() {
            let entry_path = entry.path();
            if entry_path.extension().map_or(false, |ext| ext == "yaml" || ext == "yml") {
                if let Ok(content) = std::fs::read_to_string(entry_path) {
                    if serde_yaml::from_str::<serde_yaml::Value>(&content).is_err() {
                        issues.push(HealthIssue {
                            severity: "warning".to_string(),
                            code: "invalid_yaml".to_string(),
                            message: format!("Schedule file '{}' contains invalid YAML", entry_path.file_name().unwrap_or_default().to_string_lossy()),
                            path: entry_path.to_string_lossy().to_string(),
                            repairable: false,
                        });
                    }
                }
            }
        }
    }

    // 7. Validate skill files
    let skills_dir = bizforge_dir.join("skills");
    if skills_dir.is_dir() {
        for entry in WalkDir::new(&skills_dir).max_depth(2).into_iter().flatten() {
            let entry_path = entry.path();
            if entry_path.extension().map_or(false, |ext| ext == "md" || ext == "yaml" || ext == "yml") {
                if let Ok(content) = std::fs::read_to_string(entry_path) {
                    if !content.trim().is_empty() && parse_skill_frontmatter(&content, entry_path).is_none() {
                        issues.push(HealthIssue {
                            severity: "info".to_string(),
                            code: "corrupt_frontmatter".to_string(),
                            message: format!("Skill file '{}' has missing or invalid frontmatter", entry_path.file_name().unwrap_or_default().to_string_lossy()),
                            path: entry_path.to_string_lossy().to_string(),
                            repairable: false,
                        });
                    }
                }
            }
        }
    }

    let healthy = issues.iter().all(|i| i.severity != "error");
    Ok(WorkspaceHealthReport {
        healthy,
        issues,
        checked_at: chrono_now(),
    })
}

/// Repair workspace: fix repairable issues (missing dirs, missing template files)
#[tauri::command]
pub async fn repair_workspace(path: String) -> Result<RepairResult, String> {
    let workspace_root = expand_tilde(&path);
    let bizforge_dir = if workspace_root.ends_with(".bizforge") {
        workspace_root.clone()
    } else {
        workspace_root.join(".bizforge")
    };

    let parent_name = bizforge_dir
        .parent()
        .and_then(|p| p.file_name())
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "Workspace".to_string());

    let mut repaired = Vec::new();
    let mut failed = Vec::new();

    // 1. Create .bizforge/ root if missing
    if !bizforge_dir.exists() {
        match std::fs::create_dir_all(&bizforge_dir) {
            Ok(()) => repaired.push("Created .bizforge/ directory".to_string()),
            Err(e) => {
                failed.push(format!("Failed to create .bizforge/: {}", e));
                let health_after = check_workspace_health(path).await?;
                return Ok(RepairResult { repaired, failed, health_after });
            }
        }
    }

    // 2. Create required subdirectories
    for dir_name in REQUIRED_DIRS {
        let dir_path = bizforge_dir.join(dir_name);
        if !dir_path.exists() {
            match std::fs::create_dir_all(&dir_path) {
                Ok(()) => repaired.push(format!("Created {}/ directory", dir_name)),
                Err(e) => failed.push(format!("Failed to create {}/: {}", dir_name, e)),
            }
        }
    }

    // 3. Create or repair SYSTEM.md
    let system_md_path = bizforge_dir.join("SYSTEM.md");
    let needs_system_md = if !system_md_path.exists() {
        true
    } else if let Ok(content) = std::fs::read_to_string(&system_md_path) {
        if content.trim().is_empty() {
            true
        } else if parse_frontmatter_name(&content).is_none() {
            // Back up the corrupt file
            let backup_path = bizforge_dir.join("SYSTEM.md.bak");
            match std::fs::copy(&system_md_path, &backup_path) {
                Ok(_) => repaired.push(format!("Backed up corrupt SYSTEM.md to SYSTEM.md.bak")),
                Err(e) => failed.push(format!("Failed to back up SYSTEM.md: {}", e)),
            }
            true
        } else {
            false
        }
    } else {
        false
    };

    if needs_system_md {
        let system_content = format!(
            "---\nname: {}\ndescription: A Bizforge workspace\ncreated_at: {}\n---\n\n# {}\n\nA Bizforge workspace.\n",
            parent_name, chrono_now(), parent_name
        );
        match std::fs::write(&system_md_path, &system_content) {
            Ok(()) => repaired.push("Created SYSTEM.md with default template".to_string()),
            Err(e) => failed.push(format!("Failed to write SYSTEM.md: {}", e)),
        }
    }

    // 4. Create COMPANY.md if missing
    let company_md_path = bizforge_dir.join("COMPANY.md");
    if !company_md_path.exists() {
        let company_content = "---\nname: My Organization\n---\n\n# Organization\n\nConfigure your organization details here.\n";
        match std::fs::write(&company_md_path, company_content) {
            Ok(()) => repaired.push("Created COMPANY.md with default template".to_string()),
            Err(e) => failed.push(format!("Failed to write COMPANY.md: {}", e)),
        }
    }

    // Re-check health after repairs
    let health_after = check_workspace_health(path).await?;

    Ok(RepairResult {
        repaired,
        failed,
        health_after,
    })
}

// ── Adapter Detection ───────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize)]
pub struct AdapterStatus {
    pub id: String,
    pub name: String,
    pub installed: bool,
    pub version: Option<String>,
    pub path: Option<String>,
    pub running: bool,
    pub install_hint: String,
}

/// Detect which adapters are installed on the user's system
#[tauri::command]
pub async fn detect_adapters() -> Result<Vec<AdapterStatus>, String> {
    let adapters = vec![
        detect_osa().await,
        detect_binary("claude-code", "Claude Code", "claude", "npm install -g @anthropic-ai/claude-code").await,
        detect_binary("codex", "Codex", "codex", "npm install -g @openai/codex").await,
        detect_binary_with_port("openclaw", "OpenClaw", "openclaw", 8100, "npm install -g openclaw").await,
        detect_jidoclaw().await,
        detect_binary("hermes", "Hermes Agent", "hermes-agent", "cargo install hermes-agent").await,
        detect_binary("bash", "Bash", "bash", "Already installed").await,
        AdapterStatus {
            id: "http".to_string(),
            name: "HTTP".to_string(),
            installed: true,
            version: None,
            path: None,
            running: true,
            install_hint: "No installation needed".to_string(),
        },
    ];
    Ok(adapters)
}

/// Install an adapter by running its install command
#[tauri::command]
pub async fn install_adapter(adapter_id: String) -> Result<String, String> {
    let (program, args): (&str, Vec<&str>) = match adapter_id.as_str() {
        "claude-code" => ("npm", vec!["install", "-g", "@anthropic-ai/claude-code"]),
        "codex" => ("npm", vec!["install", "-g", "@openai/codex"]),
        "openclaw" => ("npm", vec!["install", "-g", "openclaw"]),
        "hermes" => ("cargo", vec!["install", "hermes-agent"]),
        "jidoclaw" => {
            // Use JidoClaw's actual install script
            let output = tokio::process::Command::new("bash")
                .args(["-c", "curl -fsSL https://raw.githubusercontent.com/robertohluna/jido_claw/main/install.sh | bash"])
                .output()
                .await
                .map_err(|e| format!("Failed to run JidoClaw installer: {}", e))?;
            if output.status.success() {
                return Ok(String::from_utf8_lossy(&output.stdout).to_string());
            } else {
                return Err(format!(
                    "JidoClaw installation failed:\n{}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }
        }
        "osa" => {
            // Use OSA's actual install script
            let output = tokio::process::Command::new("bash")
                .args(["-c", "curl -fsSL https://raw.githubusercontent.com/Miosa-osa/OSA/main/install.sh | bash"])
                .output()
                .await
                .map_err(|e| format!("Failed to run OSA installer: {}", e))?;
            if output.status.success() {
                return Ok(String::from_utf8_lossy(&output.stdout).to_string());
            } else {
                return Err(format!(
                    "OSA installation failed:\n{}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }
        }
        _ => return Err(format!("No installer for adapter: {}", adapter_id)),
    };

    let output = tokio::process::Command::new(program)
        .args(&args)
        .output()
        .await
        .map_err(|e| format!("Failed to run installer: {}", e))?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}

// ── Adapter Detection Helpers ───────────────────────────────────────────────

async fn detect_osa() -> AdapterStatus {
    // Check for osa binary first, then optimal_system_agent
    let (installed, version, path) = if let Some((v, p)) = which_and_version("osa").await {
        (true, Some(v), Some(p))
    } else if let Some((v, p)) = which_and_version("optimal_system_agent").await {
        (true, Some(v), Some(p))
    } else {
        (false, None, None)
    };

    // Check if Elixir is installed (prerequisite)
    let elixir_installed = which_and_version("elixir").await.is_some();

    // Try health check on both ports to detect running instance and get version
    let mut running = false;
    let mut health_version = None;
    for port in [9090, 9089] {
        if let Some(v) = osa_health_check(port).await {
            running = true;
            health_version = Some(v);
            break;
        }
        // Fall back to port check if health endpoint didn't respond with JSON
        if !running && check_port_listening(port).await {
            running = true;
        }
    }

    // Prefer health-derived version over binary --version
    let final_version = health_version.or(version);

    AdapterStatus {
        id: "osa".to_string(),
        name: "OSA".to_string(),
        installed: installed || running || elixir_installed,
        version: final_version,
        path,
        running,
        install_hint: "brew install miosa/tap/osa".to_string(),
    }
}

/// Hit OSA /health endpoint via raw TCP and parse version from JSON response
async fn osa_health_check(port: u16) -> Option<String> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::time::{timeout, Duration};

    let addr = format!("127.0.0.1:{}", port);
    let mut stream = timeout(Duration::from_secs(2), tokio::net::TcpStream::connect(&addr))
        .await
        .ok()?
        .ok()?;

    let request = format!(
        "GET /health HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nConnection: close\r\n\r\n",
        port
    );
    stream.write_all(request.as_bytes()).await.ok()?;

    let mut buf = vec![0u8; 4096];
    let n = timeout(Duration::from_secs(2), stream.read(&mut buf))
        .await
        .ok()?
        .ok()?;

    let response = String::from_utf8_lossy(&buf[..n]);

    // Check for 200 OK
    if !response.contains("200") {
        return None;
    }

    // Find JSON body after \r\n\r\n
    if let Some(body_start) = response.find("\r\n\r\n") {
        let body = &response[body_start + 4..];
        // Extract version from JSON (simple parse — look for "version":"...")
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(body) {
            if let Some(v) = json.get("version").and_then(|v| v.as_str()) {
                return Some(v.to_string());
            }
        }
    }

    // At least we know it's running — return a generic version
    Some("unknown".to_string())
}

// ── OSA Setup ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize)]
pub struct OsaSetupResult {
    pub step: String,
    pub success: bool,
    pub message: String,
}

/// Full OSA setup assistant: check prerequisites, find/build/start OSA
#[tauri::command]
pub async fn setup_osa(osa_path: Option<String>) -> Result<Vec<OsaSetupResult>, String> {
    let mut results = Vec::new();

    // Step 1: Check Elixir prerequisite
    let elixir_ok = which_and_version("elixir").await;
    results.push(OsaSetupResult {
        step: "elixir".to_string(),
        success: elixir_ok.is_some(),
        message: match &elixir_ok {
            Some((v, _)) => format!("Elixir found: {}", v),
            None => "Elixir not found. Install with: brew install elixir".to_string(),
        },
    });
    if elixir_ok.is_none() {
        return Ok(results);
    }

    // Step 2: Check Erlang/OTP prerequisite
    let erl_ok = which_and_version("erl").await;
    results.push(OsaSetupResult {
        step: "erlang".to_string(),
        success: erl_ok.is_some(),
        message: match &erl_ok {
            Some((v, _)) => format!("Erlang found: {}", v),
            None => "Erlang/OTP not found. Install with: brew install erlang".to_string(),
        },
    });
    if erl_ok.is_none() {
        return Ok(results);
    }

    // Step 3: Locate OSA directory — if not found, attempt fresh install
    let mut osa_dir = find_osa_directory(osa_path.as_deref()).await;
    if osa_dir.is_none() {
        results.push(OsaSetupResult {
            step: "locate".to_string(),
            success: false,
            message: "OSA not found locally. Running installer...".to_string(),
        });
        // Run OSA's official install script (installs to ~/.osa/src)
        let install_result = tokio::process::Command::new("bash")
            .args(["-c", "curl -fsSL https://raw.githubusercontent.com/Miosa-osa/OSA/main/install.sh | bash"])
            .output()
            .await;
        match install_result {
            Ok(output) if output.status.success() => {
                results.push(OsaSetupResult {
                    step: "install".to_string(),
                    success: true,
                    message: "OSA installed successfully via install script".to_string(),
                });
                // Re-search for the directory post-install
                osa_dir = find_osa_directory(None).await;
            }
            Ok(output) => {
                results.push(OsaSetupResult {
                    step: "install".to_string(),
                    success: false,
                    message: format!(
                        "Install script failed: {}",
                        String::from_utf8_lossy(&output.stderr).lines().take(5).collect::<Vec<_>>().join("\n")
                    ),
                });
                return Ok(results);
            }
            Err(e) => {
                results.push(OsaSetupResult {
                    step: "install".to_string(),
                    success: false,
                    message: format!("Could not run installer: {}", e),
                });
                return Ok(results);
            }
        }
    }
    results.push(OsaSetupResult {
        step: "locate".to_string(),
        success: osa_dir.is_some(),
        message: match &osa_dir {
            Some(p) => format!("OSA found at: {}", p.display()),
            None => "OSA directory still not found after install attempt".to_string(),
        },
    });
    let osa_dir = match osa_dir {
        Some(d) => d,
        None => return Ok(results),
    };

    // Step 4: Check if deps are fetched
    let deps_dir = osa_dir.join("deps");
    let has_deps = deps_dir.exists() && std::fs::read_dir(&deps_dir).map(|mut d| d.next().is_some()).unwrap_or(false);
    if !has_deps {
        results.push(OsaSetupResult {
            step: "deps".to_string(),
            success: false,
            message: "Dependencies not fetched. Running mix deps.get...".to_string(),
        });
        let deps_result = tokio::process::Command::new("mix")
            .arg("deps.get")
            .current_dir(&osa_dir)
            .output()
            .await;
        match deps_result {
            Ok(output) if output.status.success() => {
                results.push(OsaSetupResult {
                    step: "deps".to_string(),
                    success: true,
                    message: "Dependencies fetched successfully".to_string(),
                });
            }
            Ok(output) => {
                results.push(OsaSetupResult {
                    step: "deps".to_string(),
                    success: false,
                    message: format!("mix deps.get failed: {}", String::from_utf8_lossy(&output.stderr)),
                });
                return Ok(results);
            }
            Err(e) => {
                results.push(OsaSetupResult {
                    step: "deps".to_string(),
                    success: false,
                    message: format!("Failed to run mix: {}", e),
                });
                return Ok(results);
            }
        }
    } else {
        results.push(OsaSetupResult {
            step: "deps".to_string(),
            success: true,
            message: "Dependencies already fetched".to_string(),
        });
    }

    // Step 5: Compile (dev mode — faster than release build)
    let compiled = osa_dir.join("_build/dev/lib/optimal_system_agent");
    if !compiled.exists() {
        results.push(OsaSetupResult {
            step: "build".to_string(),
            success: false,
            message: "Compiling OSA...".to_string(),
        });
        let build_result = tokio::process::Command::new("mix")
            .arg("compile")
            .current_dir(&osa_dir)
            .output()
            .await;
        match build_result {
            Ok(output) if output.status.success() => {
                results.push(OsaSetupResult {
                    step: "build".to_string(),
                    success: true,
                    message: "Compiled successfully".to_string(),
                });
            }
            Ok(output) => {
                results.push(OsaSetupResult {
                    step: "build".to_string(),
                    success: false,
                    message: format!("Compilation failed: {}", String::from_utf8_lossy(&output.stderr)),
                });
                return Ok(results);
            }
            Err(e) => {
                results.push(OsaSetupResult {
                    step: "build".to_string(),
                    success: false,
                    message: format!("Failed to run mix compile: {}", e),
                });
                return Ok(results);
            }
        }
    } else {
        results.push(OsaSetupResult {
            step: "build".to_string(),
            success: true,
            message: "Already compiled".to_string(),
        });
    }

    // Step 6: Check if already running
    let already_running = osa_health_check(9090).await.is_some()
        || osa_health_check(9089).await.is_some();

    if already_running {
        results.push(OsaSetupResult {
            step: "start".to_string(),
            success: true,
            message: "OSA is already running".to_string(),
        });
    } else {
        // Try release bin first, fall back to `mix run --no-halt` (dev mode)
        let release_bin = osa_dir.join("_build/prod/rel/osagent/bin/osagent");
        let start_result = if release_bin.exists() {
            tokio::process::Command::new(release_bin.to_string_lossy().to_string())
                .arg("daemon")
                .current_dir(&osa_dir)
                .output()
                .await
        } else {
            // Dev mode: start with mix in background via scripts/start.sh or mix run
            let start_script = osa_dir.join("scripts/start.sh");
            if start_script.exists() {
                tokio::process::Command::new("bash")
                    .arg(start_script.to_string_lossy().to_string())
                    .current_dir(&osa_dir)
                    .output()
                    .await
            } else {
                tokio::process::Command::new("mix")
                    .args(["run", "--no-halt"])
                    .current_dir(&osa_dir)
                    .env("MIX_ENV", "dev")
                    .output()
                    .await
            }
        };
        match start_result {
            Ok(output) if output.status.success() => {
                // Give it a moment to start
                tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;
                results.push(OsaSetupResult {
                    step: "start".to_string(),
                    success: true,
                    message: "OSA started".to_string(),
                });
            }
            Ok(output) => {
                results.push(OsaSetupResult {
                    step: "start".to_string(),
                    success: false,
                    message: format!("Failed to start OSA: {}", String::from_utf8_lossy(&output.stderr)),
                });
                return Ok(results);
            }
            Err(e) => {
                results.push(OsaSetupResult {
                    step: "start".to_string(),
                    success: false,
                    message: format!("Failed to start OSA: {}", e),
                });
                return Ok(results);
            }
        }
    }

    // Step 7: Final health check
    let mut healthy = false;
    for port in [9090, 9089] {
        if osa_health_check(port).await.is_some() {
            healthy = true;
            results.push(OsaSetupResult {
                step: "health".to_string(),
                success: true,
                message: format!("OSA responding on port {}", port),
            });
            break;
        }
    }
    if !healthy {
        results.push(OsaSetupResult {
            step: "health".to_string(),
            success: false,
            message: "OSA started but health check failed. It may still be booting.".to_string(),
        });
    }

    Ok(results)
}

/// Find OSA directory: use provided path, or search common locations
async fn find_osa_directory(explicit_path: Option<&str>) -> Option<PathBuf> {
    // If user provided a path, validate it
    if let Some(path) = explicit_path {
        let p = PathBuf::from(path);
        if is_osa_directory(&p) {
            return Some(p);
        }
        return None;
    }

    // Search common locations — includes ~/.osa/src (default install.sh target)
    let home = dirs_home();
    let candidates = vec![
        home.join(".osa/src"),
        home.join(".osa/agent"),
        home.join(".osa"),
        home.join("optimal-system-agent"),
        home.join("OptimalSystemAgent"),
        home.join("Desktop/MIOSA/code/OptimalSystemAgent"),
        home.join("code/OptimalSystemAgent"),
        home.join("projects/OptimalSystemAgent"),
        home.join("src/OptimalSystemAgent"),
    ];

    for candidate in candidates {
        if is_osa_directory(&candidate) {
            return Some(candidate);
        }
    }

    None
}

/// Check if a directory looks like an OSA project (has mix.exs with :optimal_system_agent)
fn is_osa_directory(path: &Path) -> bool {
    let mix_exs = path.join("mix.exs");
    if !mix_exs.exists() {
        return false;
    }
    if let Ok(content) = std::fs::read_to_string(&mix_exs) {
        content.contains("optimal_system_agent") || content.contains(":osagent")
    } else {
        false
    }
}

/// Get user home directory
fn dirs_home() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
}

async fn detect_jidoclaw() -> AdapterStatus {
    // Check for jido/jidoclaw binary
    let (installed, version, path) = if let Some((v, p)) = which_and_version("jido").await {
        (true, Some(v), Some(p))
    } else if let Some((v, p)) = which_and_version("jidoclaw").await {
        (true, Some(v), Some(p))
    } else {
        // Check if ~/.jido directory exists (installed via script)
        let jido_dir = dirs_home().join(".jido");
        if jido_dir.exists() {
            (true, None, Some(jido_dir.to_string_lossy().to_string()))
        } else {
            (false, None, None)
        }
    };

    // Check port 4000 (LiveView dashboard) for running instance
    let running = check_port_listening(4000).await;

    AdapterStatus {
        id: "jidoclaw".to_string(),
        name: "JidoClaw".to_string(),
        installed: installed || running,
        version,
        path,
        running,
        install_hint: "curl -fsSL https://raw.githubusercontent.com/robertohluna/jido_claw/main/install.sh | bash".to_string(),
    }
}

async fn detect_binary(id: &str, name: &str, bin: &str, hint: &str) -> AdapterStatus {
    let (installed, version, path) = match which_and_version(bin).await {
        Some((v, p)) => (true, Some(v), Some(p)),
        None => (false, None, None),
    };

    AdapterStatus {
        id: id.to_string(),
        name: name.to_string(),
        installed,
        version,
        path,
        running: installed,
        install_hint: hint.to_string(),
    }
}

async fn detect_binary_with_port(
    id: &str,
    name: &str,
    bin: &str,
    port: u16,
    hint: &str,
) -> AdapterStatus {
    let (installed, version, path) = match which_and_version(bin).await {
        Some((v, p)) => (true, Some(v), Some(p)),
        None => (false, None, None),
    };

    let running = check_port_listening(port).await;

    AdapterStatus {
        id: id.to_string(),
        name: name.to_string(),
        installed: installed || running,
        version,
        path,
        running,
        install_hint: hint.to_string(),
    }
}

/// Run `which <binary>` and `<binary> --version` to get path and version
async fn which_and_version(bin: &str) -> Option<(String, String)> {
    let which_output = tokio::process::Command::new("which")
        .arg(bin)
        .output()
        .await
        .ok()?;

    if !which_output.status.success() {
        return None;
    }

    let path = String::from_utf8_lossy(&which_output.stdout)
        .trim()
        .to_string();

    if path.is_empty() {
        return None;
    }

    // Try to get version
    let version = if let Ok(ver_output) = tokio::process::Command::new(bin)
        .arg("--version")
        .output()
        .await
    {
        if ver_output.status.success() {
            let raw = String::from_utf8_lossy(&ver_output.stdout)
                .trim()
                .to_string();
            // Take only the first line
            raw.lines().next().unwrap_or(&raw).to_string()
        } else {
            "unknown".to_string()
        }
    } else {
        "unknown".to_string()
    };

    Some((version, path))
}

/// Check if a TCP port is listening on 127.0.0.1 (no external deps needed)
async fn check_port_listening(port: u16) -> bool {
    tokio::net::TcpStream::connect(format!("127.0.0.1:{}", port))
        .await
        .is_ok()
}

// ── OSA Stop ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OsaStopResult {
    pub success: bool,
    pub message: String,
}

#[tauri::command]
pub async fn stop_osa() -> Result<OsaStopResult, String> {
    // Find the OSA process by checking which port it's on, then use lsof to get PID
    let mut osa_port: Option<u16> = None;
    for port in [9090u16, 9089] {
        if osa_health_check(port).await.is_some() {
            osa_port = Some(port);
            break;
        }
    }

    let port = match osa_port {
        Some(p) => p,
        None => {
            return Ok(OsaStopResult {
                success: false,
                message: "OSA is not running (no health response on 9090 or 9089)".to_string(),
            });
        }
    };

    // Use lsof to find the PID listening on the port
    let lsof_output = tokio::process::Command::new("lsof")
        .args(["-ti", &format!(":{}", port)])
        .output()
        .await
        .map_err(|e| format!("Failed to run lsof: {}", e))?;

    let pids_str = String::from_utf8_lossy(&lsof_output.stdout).trim().to_string();
    if pids_str.is_empty() {
        return Ok(OsaStopResult {
            success: false,
            message: format!(
                "OSA responds on port {} but could not find process PID via lsof",
                port
            ),
        });
    }

    // Kill each PID (there may be parent + child)
    let mut killed = false;
    for pid_str in pids_str.lines() {
        if let Ok(pid) = pid_str.trim().parse::<u32>() {
            let kill_result = tokio::process::Command::new("kill")
                .args(["-TERM", &pid.to_string()])
                .output()
                .await;

            if kill_result.is_ok() {
                killed = true;
            }
        }
    }

    if !killed {
        return Ok(OsaStopResult {
            success: false,
            message: format!("Failed to terminate OSA processes on port {}", port),
        });
    }

    // Brief wait then verify it's down
    tokio::time::sleep(std::time::Duration::from_millis(1500)).await;
    let still_running = osa_health_check(port).await.is_some();

    Ok(OsaStopResult {
        success: !still_running,
        message: if still_running {
            "Sent SIGTERM but OSA is still responding — may need SIGKILL".to_string()
        } else {
            format!("OSA stopped (was on port {})", port)
        },
    })
}

// ── System Resources ─────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemResourceInfo {
    pub memory_total_gb: f64,
    pub memory_used_gb: f64,
    pub memory_free_gb: f64,
    pub memory_used_pct: f64,
    pub cpu_usage_pct: f64,
    pub cpu_cores: usize,
    pub cpu_brand: String,
    pub os_name: String,
    pub os_arch: String,
    pub hostname: String,
    pub pid: u32,
    pub app_memory_mb: f64,
    pub uptime_seconds: u64,
}

#[tauri::command]
pub async fn get_system_resources() -> Result<SystemResourceInfo, String> {
    use sysinfo::System;

    let mut sys = System::new_all();
    // Brief pause to allow CPU measurement to stabilize
    std::thread::sleep(std::time::Duration::from_millis(200));
    sys.refresh_all();

    let total_mem = sys.total_memory() as f64 / (1024.0 * 1024.0 * 1024.0);
    let used_mem = sys.used_memory() as f64 / (1024.0 * 1024.0 * 1024.0);
    let free_mem = total_mem - used_mem;
    let used_pct = if total_mem > 0.0 {
        (used_mem / total_mem) * 100.0
    } else {
        0.0
    };

    let cpu_usage = sys.global_cpu_usage() as f64;
    let cpu_cores = sys.cpus().len();
    let cpu_brand = sys
        .cpus()
        .first()
        .map(|c| c.brand().to_string())
        .unwrap_or_else(|| "Unknown".to_string());

    // Get current process memory
    let current_pid = sysinfo::get_current_pid().unwrap_or(sysinfo::Pid::from(0));
    let app_memory_mb = sys
        .process(current_pid)
        .map(|p| p.memory() as f64 / (1024.0 * 1024.0))
        .unwrap_or(0.0);

    let uptime = System::uptime();

    Ok(SystemResourceInfo {
        memory_total_gb: (total_mem * 10.0).round() / 10.0,
        memory_used_gb: (used_mem * 10.0).round() / 10.0,
        memory_free_gb: (free_mem * 10.0).round() / 10.0,
        memory_used_pct: (used_pct * 10.0).round() / 10.0,
        cpu_usage_pct: (cpu_usage * 10.0).round() / 10.0,
        cpu_cores,
        cpu_brand,
        os_name: System::name().unwrap_or_else(|| "Unknown".to_string()),
        os_arch: std::env::consts::ARCH.to_string(),
        hostname: System::host_name().unwrap_or_else(|| "Unknown".to_string()),
        pid: std::process::id(),
        app_memory_mb: (app_memory_mb * 10.0).round() / 10.0,
        uptime_seconds: uptime,
    })
}
