# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Announcements API

All endpoints require a bearer token. Company admins can create, update, and
delete announcements for their company. `GET /api/v1/announcements` returns all
company announcements to admins (including scheduled or inactive announcements)
and only currently visible, not-yet-dismissed announcements to employees.

Create an announcement with `POST /api/v1/announcements`:

```json
{
  "announcement": {
    "title": "Office walking challenge",
    "message": "Join this month's walking challenge.",
    "starts_at": "2026-11-01T09:00:00Z",
    "ends_at": "2026-11-30T23:59:59Z",
    "active": true
  }
}
```

`starts_at` defaults to the current time and `ends_at` is optional. Visibility
requires `active: true`, a start time that has passed, and either no end time or
an end time in the future. Employees can dismiss a visible announcement with
`POST /api/v1/announcements/:id/dismiss`; dismissal is remembered per user.

Admins can update an announcement with `PATCH /api/v1/announcements/:id` or
delete it with `DELETE /api/v1/announcements/:id`.

### Push notifications

The React Native app should request notification permission, obtain an Expo
Push Token, and register it with `POST /api/v1/push_tokens`:

```json
{ "push_token": { "token": "ExponentPushToken[...]" } }
```

Use `DELETE /api/v1/push_tokens` with the same request body when logging out or
unregistering the device. Registering a token while signed into another account
transfers that installation token to the current account. When an announcement
becomes visible, the backend snapshots active company users' registered devices
and sends notifications in batches. `delivered` means Expo accepted the push
ticket, not confirmed delivery to the device; `failed` and `unknown` outcomes
remain inspectable in `announcement_deliveries`. Network timeouts are marked
unknown because Expo may have accepted the request before the connection failed.
An optional `EXPO_ACCESS_TOKEN` environment variable is used for Expo push
security.

Push delivery and real-time broadcasting run independently. Delivery progress
is persisted per announcement/device. Expo transient response errors retry
pending devices only; invalid tokens are removed. A timeout's unknown result is
not automatically resent to avoid duplicate pushes. A process interruption
after Expo accepts a request but before its ticket is saved can still result in
an unknown outcome; external push providers do not provide a transaction with
the application database.

In production, the recurring Solid Queue worker runs announcement recovery
every five minutes. Ensure the production job worker and recurring-task
dispatcher are running, or scheduled announcements and retries will not run.

### Real-time updates and comments

ActionCable is available at `/cable`. Connect using the current JWT as the
`token` query parameter, then subscribe to `AnnouncementsChannel` to receive
announcement and comment events for the authenticated user's company. The
channel derives the stream from the authenticated user's company and does not
accept a client-supplied company ID. Scheduled announcements are broadcast when
they become visible.

Events include `announcement_created`, `announcement_updated`,
`announcement_removed`, `announcement_deleted`,
`announcement_comment_created`, `announcement_comment_updated`, and
`announcement_comment_deleted`. Announcement events include the announcement
JSON or its ID; comment events include the comment JSON or its ID. Outbox events
include an `event_key` so clients can ignore a duplicate if a worker is
interrupted after broadcasting but before recording completion. Broadcast
delivery is at-least-once in that narrow failure case.

Comments are listed/created at
`/api/v1/announcements/:announcement_id/comments`. Replies use the same endpoint
with a `parent_id` referencing a top-level comment. Further nested replies are
not allowed. Listing is chronological and paginated with `page` (default 1) and
`per_page` (default 30, maximum 100). The response includes `pagination` fields
for page, per-page size, total count, and total pages.

```json
{
  "comment": {
    "body": "Looking forward to it!",
    "parent_id": 123
  }
}
```

Authors can edit or delete their own comments; company admins can delete any
comment. Employees can access comments only while the announcement is visible.
Deleting a parent comment also deletes its replies.
