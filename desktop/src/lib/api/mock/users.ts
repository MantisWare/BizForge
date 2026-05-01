import type { User } from "../types";

const STORAGE_KEY = "bizforge-mock-users";

const SEED_USERS: User[] = [
  {
    id: "user-admin",
    email: "admin@bizforge.dev",
    name: "Admin User",
    role: "admin",
    created_at: "2026-01-01T00:00:00Z",
  },
  {
    id: "user-dev",
    email: "dev@bizforge.dev",
    name: "Dev User",
    role: "member",
    created_at: "2026-01-15T00:00:00Z",
  },
  {
    id: "user-viewer",
    email: "viewer@bizforge.dev",
    name: "Viewer User",
    role: "viewer",
    created_at: "2026-02-01T00:00:00Z",
  },
];

function loadUsers(): User[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw !== null) return JSON.parse(raw) as User[];
  } catch {
    // corrupted — fall through to seeds
  }
  localStorage.setItem(STORAGE_KEY, JSON.stringify(SEED_USERS));
  return [...SEED_USERS];
}

function saveUsers(users: User[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(users));
}

export function mockUsers(): User[] {
  return loadUsers();
}

export function mockUserById(id: string): User | undefined {
  return loadUsers().find((u) => u.id === id);
}

export function mockCreateUser(body: Partial<User>): User {
  const users = loadUsers();
  const created: User = {
    id: `user-${Date.now()}`,
    email: body.email ?? "",
    name: body.name ?? "",
    role: body.role ?? "member",
    avatar_url: body.avatar_url,
    created_at: new Date().toISOString(),
  };
  users.unshift(created);
  saveUsers(users);
  return created;
}

export function mockUpdateUser(id: string, body: Partial<User>): User | null {
  const users = loadUsers();
  const idx = users.findIndex((u) => u.id === id);
  if (idx === -1) return null;
  const updated = { ...users[idx], ...body, id };
  users[idx] = updated;
  saveUsers(users);
  return updated;
}

export function mockDeleteUser(id: string): boolean {
  const users = loadUsers();
  const filtered = users.filter((u) => u.id !== id);
  if (filtered.length === users.length) return false;
  saveUsers(filtered);
  return true;
}
