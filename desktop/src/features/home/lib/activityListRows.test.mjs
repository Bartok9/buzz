import assert from "node:assert/strict";
import test from "node:test";

import { buildActivityListRows } from "./activityListRows.ts";

function draft(key, createdAt, updatedAt = createdAt) {
  return {
    key,
    draft: {
      channelId: "channel-1",
      content: "unfinished",
      createdAt,
      updatedAt,
      pendingImeta: [],
      selectionEnd: 0,
      selectionStart: 0,
      spoileredAttachmentUrls: [],
      status: "active",
    },
  };
}

function reminder(id, createdAt, notBefore, status = "pending") {
  return {
    id,
    createdAt,
    eventId: `event-${id}`,
    notBefore,
    content: { note: id, status },
  };
}

test("All orders messages, reminders, and drafts by activity time", () => {
  const rows = buildActivityListRows({
    drafts: [draft("older-draft", "2026-01-01T00:02:00.000Z")],
    items: [{ id: "new-agent-reply", latestActivityAt: 1767225900 }],
    reminders: [reminder("older-reminder", 1767225660, 1767232800)],
  });

  assert.deepEqual(
    rows.map((row) => row.key),
    ["inbox:new-agent-reply", "draft:older-draft", "reminder:older-reminder"],
  );
});

test("All uses a draft's last edit and excludes completed reminders", () => {
  const rows = buildActivityListRows({
    drafts: [
      draft(
        "edited-draft",
        "2026-01-01T00:01:00.000Z",
        "2026-01-01T00:05:00.000Z",
      ),
    ],
    items: [{ id: "message", latestActivityAt: 1767225780 }],
    reminders: [reminder("done", 1767225960, 1767232800, "done")],
  });

  assert.deepEqual(
    rows.map((row) => row.key),
    ["draft:edited-draft", "inbox:message"],
  );
});
