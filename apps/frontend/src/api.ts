export interface Idea {
  id: number;
  content: string;
  created_at: string;
}

declare global {
  interface Window {
    __IDEA_BOARD_CONFIG__?: { apiBaseUrl: string };
  }
}

export function apiUrl(path: string): string {
  const base = window.__IDEA_BOARD_CONFIG__?.apiBaseUrl ?? "";
  return `${base}${path}`;
}

export async function fetchIdeas(): Promise<Idea[]> {
  const res = await fetch(apiUrl("/api/ideas"));
  if (!res.ok) throw new Error(`Failed to load ideas (${res.status})`);
  return res.json();
}

export async function createIdea(content: string): Promise<Idea> {
  const res = await fetch(apiUrl("/api/ideas"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ content }),
  });
  if (!res.ok) throw new Error(`Failed to create idea (${res.status})`);
  return res.json();
}
