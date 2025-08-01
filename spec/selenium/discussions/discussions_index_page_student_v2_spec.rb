# frozen_string_literal: true

#
# Copyright (C) 2014 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

require_relative "pages/discussions_index_page"
require_relative "../helpers/items_assign_to_tray"
require_relative "pages/discussion_page"
require_relative "../common"

describe "discussions index" do
  include_context "in-process server selenium tests"

  def setup_course_and_students
    @teacher = user_with_pseudonym(active_user: true)
    @student = user_with_pseudonym(active_user: true)
    @account = Account.create(name: "New Account", default_time_zone: "UTC")
    @course = course_factory(course_name: "Aaron 101",
                             account: @account,
                             active_course: true)
    course_with_teacher(user: @teacher, active_course: true, active_enrollment: true)
    course_with_student(course: @course, active_enrollment: true)
    @student2 = user_factory(name: "second user", short_name: "second")
    user_with_pseudonym(user: @student2, active_user: true)
    @course.enroll_student(@student2, enrollment_state: "active")
  end

  context "as a student" do
    discussion1_title = "Meaning of life"
    discussion2_title = "Meaning of the universe"

    before :once do
      setup_course_and_students
      # Discussion attributes: title, message, delayed_post_at, user
      @discussion1 = @course.discussion_topics.create!(
        title: discussion1_title,
        message: "Is it really 42?",
        user: @teacher,
        pinned: false
      )
      @discussion2 = @course.discussion_topics.create!(
        title: discussion2_title,
        message: "Could it be 43?",
        delayed_post_at: 1.day.from_now,
        user: @teacher,
        locked: true,
        pinned: false
      )

      @discussion1.discussion_entries.create!(user: @student, message: "I think I read that somewhere...")
      @discussion1.discussion_entries.create!(user: @student, message: ":eyeroll:")
    end

    def login_and_visit_course(teacher, course)
      user_session(teacher)
      DiscussionsIndex.visit(course)
    end

    def create_course_and_discussion(opts)
      opts.reverse_merge!({ locked: false, pinned: false })
      course = course_factory(active_all: true)
      discussion = course.discussion_topics.create!(
        title: opts[:title],
        message: opts[:message],
        user: @teacher,
        locked: opts[:locked],
        pinned: opts[:pinned]
      )
      [course, discussion]
    end

    it "discussions can be created if setting is on" do
      @course.allow_student_discussion_topics = true
      login_and_visit_course(@student, @course)
      expect_new_page_load { DiscussionsIndex.click_add_discussion }
    end
  end

  context "discussion checkpoints" do
    include ItemsAssignToTray

    before :once do
      Account.default.enable_feature! :discussion_create
      setup_course_and_students
      sub_account = Account.create!(name: "Sub Account", parent_account: Account.default)
      @course.update!(account: sub_account)
      sub_account.enable_feature! :discussion_checkpoints
    end

    it "show checkpoint info on the index page", :ignore_js_errors do
      user_session(@teacher)
      Discussion.start_new_discussion(@course.id)
      wait_for_ajaximations
      Discussion.topic_title_input.send_keys("Test Checkpoint")
      Discussion.update_discussion_message
      Discussion.click_graded_checkbox
      Discussion.click_checkpoints_checkbox
      Discussion.reply_to_topic_points_possible_input.send_keys("10")
      Discussion.reply_to_entry_required_count_input.send_keys("1")
      Discussion.points_possible_reply_to_entry_input.send_keys("10")
      next_week = 1.week.from_now
      half_month = 2.weeks.from_now
      update_reply_to_topic_date(0, format_date_for_view(next_week))
      update_reply_to_topic_time(0, "11:59 PM")
      update_required_replies_date(0, format_date_for_view(next_week))
      update_required_replies_time(0, "11:59 PM")
      click_add_assign_to_card
      select_module_item_assignee(1, @student.name)
      update_reply_to_topic_date(1, format_date_for_view(half_month))
      update_reply_to_topic_time(1, "11:59 PM")
      update_required_replies_date(1, format_date_for_view(half_month))
      update_required_replies_time(1, "11:59 PM")
      Discussion.save_and_publish_button.click
      # student within everyone
      user_session(@student2)
      get "/courses/#{@course.id}/discussion_topics"
      expect(fj("span:contains('Reply to topic: #{format_date_for_view(next_week, :short)}')")).to be_present
      expect(fj("span:contains('Required replies (1): #{format_date_for_view(next_week, :short)}')")).to be_present
      expect(f("body")).not_to contain_jqcss("span:contains('Reply to topic: #{format_date_for_view(half_month, :short)}')")
      expect(f("body")).not_to contain_jqcss("span:contains('Required replies (1): #{format_date_for_view(half_month, :short)}')")
      # student in the second assign card
      user_session(@student)
      get "/courses/#{@course.id}/discussion_topics"
      expect(fj("span:contains('Reply to topic: #{format_date_for_view(half_month, :short)}')")).to be_present
      expect(fj("span:contains('Required replies (1): #{format_date_for_view(half_month, :short)}')")).to be_present
      expect(f("body")).not_to contain_jqcss("span:contains('Reply to topic: #{format_date_for_view(next_week, :short)}')")
      expect(f("body")).not_to contain_jqcss("span:contains('Required replies (1): #{format_date_for_view(next_week, :short)}')")
    end
  end
end
