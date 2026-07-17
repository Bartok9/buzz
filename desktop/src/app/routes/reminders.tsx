import { createFileRoute, redirect } from "@tanstack/react-router";

// Reminders is now a filter option inside the Activity dropdown, selected via
// local state rather than the URL. This redirect preserves existing history
// entries and bookmarks pointing at `/reminders` so they land in Activity
// instead of dead-ending; the user re-selects Reminders from the filter.
export const Route = createFileRoute("/reminders")({
  beforeLoad: () => {
    throw redirect({ to: "/" });
  },
});
