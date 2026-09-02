import { FormEvent, useCallback, useEffect, useState } from "react";
import { createIdea, fetchIdeas, type Idea } from "./api";

export default function App() {
  const [ideas, setIdeas] = useState<Idea[]>([]);
  const [content, setContent] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    try {
      setIdeas(await fetchIdeas());
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load ideas");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    const trimmed = content.trim();
    if (!trimmed) return;
    setSubmitting(true);
    setError(null);
    try {
      const idea = await createIdea(trimmed);
      setIdeas((prev) => [idea, ...prev]);
      setContent("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to submit idea");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <h1>Idea Board</h1>
      <p className="subtitle">Share ideas. Built for the Outmarket DevOps case study.</p>

      {error && <p className="error">{error}</p>}

      <form onSubmit={onSubmit}>
        <input
          type="text"
          placeholder="My new idea…"
          value={content}
          onChange={(e) => setContent(e.target.value)}
          disabled={submitting}
          maxLength={2000}
        />
        <button type="submit" disabled={submitting || !content.trim()}>
          Add
        </button>
      </form>

      {loading ? (
        <p className="empty">Loading…</p>
      ) : ideas.length === 0 ? (
        <p className="empty">No ideas yet. Add one above.</p>
      ) : (
        <ul>
          {ideas.map((idea) => (
            <li key={idea.id}>
              {idea.content}
              <time dateTime={idea.created_at}>
                {new Date(idea.created_at).toLocaleString()}
              </time>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
