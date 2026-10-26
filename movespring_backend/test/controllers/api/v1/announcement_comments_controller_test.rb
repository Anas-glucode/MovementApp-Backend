require "test_helper"

class Api::V1::AnnouncementCommentsControllerTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @employee = users(:two)
    @announcement = companies(:two).announcements.create!(
      title: "Team news",
      message: "Company update",
      starts_at: 1.minute.ago
    )
  end

  test "employees can comment and reply on visible company announcements" do
    post comments_path,
         params: { comment: { body: "Thanks for the update" } },
         headers: auth_headers(@employee)

    assert_response :created
    parent_id = response.parsed_body.dig("comment", "id")

    post comments_path,
         params: { comment: { body: "You're welcome", parent_id: parent_id } },
         headers: auth_headers(@employee)

    assert_response :created
    assert_equal parent_id, response.parsed_body.dig("comment", "parent_id")

    get comments_path, headers: auth_headers(@employee)

    assert_response :ok
    assert_equal 2, response.parsed_body.fetch("comments").length
  end

  test "blank and oversized comments are rejected" do
    [ "", "x" * 2_001 ].each do |body|
      assert_no_difference("AnnouncementComment.count") do
        post comments_path,
             params: { comment: { body: body } },
             headers: auth_headers(@employee)
      end

      assert_response :unprocessable_entity
    end
  end

  test "authors can edit and delete their comments" do
    comment = @announcement.announcement_comments.create!(
      user: @employee,
      body: "Original"
    )

    patch comment_path(comment),
          params: { comment: { body: "Edited" } },
          headers: auth_headers(@employee)

    assert_response :ok
    assert_equal "Edited", comment.reload.body

    delete comment_path(comment), headers: auth_headers(@employee)

    assert_response :no_content
    assert_not AnnouncementComment.exists?(comment.id)
  end

  test "employees cannot comment on another company's announcement" do
    foreign_announcement = companies(:one).announcements.create!(
      title: "Private update",
      message: "Not for this company",
      starts_at: 1.minute.ago
    )

    post "/api/v1/announcements/#{foreign_announcement.id}/comments",
         params: { comment: { body: "Intrusion" } },
         headers: auth_headers(@employee)

    assert_response :not_found
  end

  test "comments reject a parent from another announcement" do
    another_announcement = companies(:two).announcements.create!(
      title: "Another update",
      message: "Another discussion",
      starts_at: 1.minute.ago
    )
    parent = another_announcement.announcement_comments.create!(
      user: @employee,
      body: "Different thread"
    )

    assert_no_difference("AnnouncementComment.count") do
      post comments_path,
           params: { comment: { body: "Wrong thread", parent_id: parent.id } },
           headers: auth_headers(@employee)
    end

    assert_response :unprocessable_entity
  end

  test "replies cannot be nested more than one level" do
    parent = @announcement.announcement_comments.create!(
      user: @employee,
      body: "Top-level comment"
    )
    reply = @announcement.announcement_comments.create!(
      user: @employee,
      body: "Reply",
      parent: parent
    )

    assert_no_difference("AnnouncementComment.count") do
      post comments_path,
           params: { comment: { body: "Nested reply", parent_id: reply.id } },
           headers: auth_headers(@employee)
    end

    assert_response :unprocessable_entity
  end

  test "comment listing is paginated with a stable chronological order" do
    3.times do |index|
      @announcement.announcement_comments.create!(
        user: @employee,
        body: "Comment #{index}"
      )
    end

    get comments_path, params: { page: 2, per_page: 2 },
                       headers: auth_headers(@employee)

    assert_response :ok
    body = response.parsed_body
    assert_equal 2, body.dig("pagination", "page")
    assert_equal 2, body.dig("pagination", "per_page")
    assert_equal 3, body.dig("pagination", "total_count")
    assert_equal 2, body.dig("pagination", "total_pages")
    assert_equal 1, body.fetch("comments").length
  end

  test "model rejects an author from another company" do
    comment = @announcement.announcement_comments.new(
      user: users(:one),
      body: "Cross-company comment"
    )

    assert_not comment.valid?
    assert_includes comment.errors[:user], "must belong to the announcement's company"
  end

  test "comment deletions broadcast to the announcement company after the author moves" do
    comment = @announcement.announcement_comments.create!(
      user: @employee,
      body: "Original"
    )
    stream = "announcements_company_#{@announcement.company_id}"
    @employee.update!(company: companies(:one))

    assert_broadcasts(stream, 1) do
      comment.destroy!
    end

    message = ActiveSupport::JSON.decode(broadcasts(stream).last)
    assert_equal "announcement_comment_deleted", message.fetch("type")
    assert_equal comment.id, message.fetch("comment_id")
    assert_equal @announcement.id, message.fetch("announcement_id")
  end

  test "users cannot edit or delete another user's comment" do
    author = User.create!(
      company: companies(:two),
      name: "Another employee",
      email: "comment-author@example.com",
      password: "Password123!",
      role: "employee",
      status: "active"
    )
    comment = @announcement.announcement_comments.create!(
      user: author,
      body: "Author's comment"
    )

    patch comment_path(comment),
          params: { comment: { body: "Changed by someone else" } },
          headers: auth_headers(@employee)

    assert_response :forbidden

    delete comment_path(comment), headers: auth_headers(@employee)

    assert_response :forbidden
    assert_equal "Author's comment", comment.reload.body
  end

  private

  def comments_path
    "/api/v1/announcements/#{@announcement.id}/comments"
  end

  def comment_path(comment)
    "#{comments_path}/#{comment.id}"
  end

  def auth_headers(user)
    { "Authorization" => "Bearer #{TokenService.issue(user)}" }
  end
end
