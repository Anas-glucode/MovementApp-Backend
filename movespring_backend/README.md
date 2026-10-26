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
