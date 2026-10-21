   # app/jobs/purge_refresh_tokens_job.rb
   class PurgeRefreshTokensJob < ApplicationJob
     def perform
       # Delete tickets that expired or were cancelled over a week ago.
       # We keep the last week so the "stolen ticket reused" check still works.
       RefreshToken.where("expires_at < :cutoff OR revoked_at < :cutoff",
                          cutoff: 7.days.ago).delete_all
     end
   end