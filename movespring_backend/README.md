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

## Email link configuration

Set these environment variables in the deployment environment to the
corresponding front-end routes:

* `INVITATION_URL`: invitation acceptance page. The invitation token is added
  as a `token` query parameter.
* `EMAIL_VERIFICATION_URL`: email verification page. The verification token is
  added as a `token` query parameter.

Both variables are required in production. Development defaults to
`http://localhost:3000/accept-invitation` and
`http://localhost:3000/verify-email`.
