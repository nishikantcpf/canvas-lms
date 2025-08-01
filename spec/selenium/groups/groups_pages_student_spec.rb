# frozen_string_literal: true

#
# Copyright (C) 2015 - present Instructure, Inc.
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

require_relative "../common"
require_relative "../announcements/pages/announcement_index_page"
require_relative "../announcements/pages/announcement_new_edit_page"
require_relative "../discussions/pages/discussions_index_page"
require_relative "../helpers/announcements_common"
require_relative "../helpers/legacy_announcements_common"
require_relative "../helpers/conferences_common"
require_relative "../helpers/course_common"
require_relative "../helpers/discussions_common"
require_relative "../helpers/files_common"
require_relative "../helpers/google_drive_common"
require_relative "../helpers/groups_common"
require_relative "../helpers/groups_shared_examples"
require_relative "../helpers/wiki_and_tiny_common"

describe "groups" do
  include_context "in-process server selenium tests"
  include AnnouncementsCommon
  include ConferencesCommon
  include CourseCommon
  include DiscussionsCommon
  include FilesCommon
  include GoogleDriveCommon
  include GroupsCommon
  include WikiAndTinyCommon

  setup_group_page_urls

  context "as a student" do
    before :once do
      @student = User.create!(name: "Student 1")
      @teacher = User.create!(name: "Teacher 1")
      course_with_student({ user: @student, active_course: true, active_enrollment: true })
      @course.enroll_teacher(@teacher).accept!
      group_test_setup(4, 1, 1)
      # adds all students to the group
      add_users_to_group(@students + [@student], @testgroup.first)
    end

    before do
      user_session(@student)
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "home page" do
      it_behaves_like "home_page", :student

      it "only allows group members to access the group home page", priority: "1" do
        get url
        expect(f(".recent-activity-header")).to be_displayed
        verify_no_course_user_access(url)
      end

      describe "for concluded course" do
        it "is not accessible to students" do
          course = Course.create!(name: "course 1")
          teacher = User.create!(name: "Teacher 1")
          course.enroll_teacher(teacher).accept!
          student = User.create!(name: "Student 1")
          en = course.enroll_student(student)
          en.workflow_state = "active"
          en.save!
          course.reload

          category = course.group_categories.create!(name: "category")
          course.groups.create!(name: "Test Group", group_category: category)
          course.groups.first.add_user student
          course.update(conclude_at: 1.day.ago, workflow_state: "completed")

          user_session(student)
          get "/groups/#{course.groups.first.id}"

          expect(driver.current_url).to eq dashboard_url
          expect(f(".ic-flash-error")).to be_displayed
        end

        it "is accessible to teachers" do
          course = Course.create!(name: "course 1")
          teacher = User.create!(name: "Teacher 1")
          course.enroll_teacher(teacher).accept!
          student = User.create!(name: "Student 1")
          en = course.enroll_student(student)
          en.workflow_state = "active"
          en.save!
          course.reload

          category = course.group_categories.create!(name: "category")
          course.groups.create!(name: "Test Group", group_category: category)
          course.groups.first.add_user student
          course.update(conclude_at: 1.day.ago, workflow_state: "completed")

          user_session(teacher)
          url = "/groups/#{course.groups.first.id}"
          get url

          expect(driver.current_url).to end_with url
        end
      end

      it "hides groups for inaccessible courses in groups list", priority: "2" do
        term = EnrollmentTerm.find(@course.enrollment_term_id)
        term.end_at = 2.days.ago
        term.save!
        @course.restrict_student_past_view = true
        @course.save
        get "/groups"
        expect(f("#content")).not_to contain_css(".previous_groups")
      end
    end

    describe "announcements page v2" do
      it_behaves_like "announcements_page_v2", :student

      it "allows group members to delete their own announcements" do
        announcement = @testgroup.first.announcements.create!(
          title: "Announcement by #{@student.name}",
          message: "sup",
          user: @student
        )
        get announcements_page
        expect(ff(".ic-announcement-row").size).to eq 1
        AnnouncementIndex.delete_announcement_manually(announcement.title)
        expect(f(".announcements-v2__wrapper")).not_to contain_css(".ic-announcement-row")
      end

      it "allows any group member to create an announcement" do
        @testgroup.first.announcements.create!(
          title: "Announcement by #{@user.name}",
          message: "sup",
          user: @user
        )
        # Log in as a new student to see if we can make an announcement
        user_session(@students.first)
        AnnouncementNewEdit.visit_new(@testgroup.first)
        AnnouncementNewEdit.add_message("New Announcement")
        AnnouncementNewEdit.add_title("New Title")
        AnnouncementNewEdit.submit_announcement_form
        expect(driver.current_url).to include(AnnouncementNewEdit
                                              .individual_announcement_url(Announcement.last))
      end

      it "allows group members to edit their own announcements" do
        announcement = @testgroup.first.announcements.create!(
          title: "Announcement by #{@user.name}",
          message: "The Force Awakens",
          user: @user
        )
        get announcements_page
        expect_new_page_load { AnnouncementIndex.click_on_announcement(announcement.title) }
        expect(driver.current_url).to include AnnouncementNewEdit.individual_announcement_url(announcement)
      end

      it "edit page should succeed for their own announcements" do
        announcement = @testgroup.first.announcements.create!(
          title: "Announcement by #{@user.name}",
          message: "The Force Awakens",
          user: @user
        )
        # NOTE: announcement_url includes a leading '/'
        AnnouncementNewEdit.edit_group_announcement(@testgroup.first,
                                                    announcement,
                                                    "Canvas will be rewritten in chicken")
        announcement.reload
        # Editing *appends* to existing message, and the resulting announcement's
        # message is wrapped in paragraph tags
        expect(announcement.message).to eq(
          "<p>The Force AwakensCanvas will be rewritten in chicken</p>"
        )
      end

      it "does not allow group members to edit someone else's announcement" do
        announcement = @testgroup.first.announcements.create!(
          title: "Announcement by #{@user.name}",
          message: "sup",
          user: @user
        )
        user_session(@students.first)
        get announcements_page
        expect(ff(".ic-announcement-row").size).to eq 1
        expect_new_page_load { AnnouncementIndex.click_on_announcement(announcement.title) }
        expect(f("#content-wrapper")).not_to contain_css(".edit-btn")
      end

      it "student in group can see teachers announcement in index", :ignore_js_errors do
        announcement = @testgroup.first.announcements.create!(
          title: "Group Announcement",
          message: "Group",
          user: @teacher
        )
        user_session(@students.first)
        AnnouncementIndex.visit_groups_index(@testgroup.first)
        expect_new_page_load { AnnouncementIndex.click_on_announcement(announcement.title) }
        expect(f('[data-testid="message_title"]')).to include_text("Group Announcement")
        expect(f(".userMessage").text).to eq "Group"
      end

      it "only allows group members to access announcements" do
        get announcements_page
        verify_no_course_user_access(announcements_page)
      end

      it "does not allow group members to edit someone else's announcement via discussion page", priority: "1" do
        announcement = @testgroup.first.announcements.create!(
          title: "foobers",
          user: @students.first,
          message: "sup",
          workflow_state: "published"
        )
        user_session(@student)
        get DiscussionsIndex.individual_discussion_url(announcement)
        expect(f("#content")).not_to contain_css(".edit-btn")
      end

      it "allows all group members to see announcements", :ignore_js_errors, priority: "1" do
        @announcement = @testgroup.first.announcements.create!(
          title: "Group Announcement",
          message: "Group",
          user: @teacher
        )
        AnnouncementIndex.visit_groups_index(@testgroup.first)
        expect(ff(".ic-announcement-row").size).to eq 1
        expect_new_page_load { ff('[data-testId="single-announcement-test-id"]')[0].click }
        expect(f('[data-testid="message_title"]')).to include_text(@announcement.title)
      end
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "people page" do
      it_behaves_like "people_page", :student

      it "displays and show a list of group members", priority: "1" do
        get people_page
        # Checks that all students and teachers created in setup are listed on page
        expect(ff(".student_roster .user_name").size).to eq 5
        expect(ff(".teacher_roster .user_name").size).to eq 1
      end

      it "shows only active members in groups to students", priority: "2" do
        get people_page
        student_enrollment = StudentEnrollment.last
        student = User.find(student_enrollment.user_id)
        expect(f(".student_roster")).to contain_css("a[href*='#{student.id}']")
        student_enrollment.workflow_state = "inactive"
        student_enrollment.save!
        refresh_page
        expect(f(".student_roster")).not_to contain_css("a[href*='#{student.id}']")
      end

      it "allows access to people page only within the scope of a group", priority: "1" do
        get people_page
        expect(f(".roster.student_roster")).to be_displayed
        verify_no_course_user_access(people_page)
      end
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "discussions page" do
      it_behaves_like "discussions_page", :student

      it "allows discussions to be created within a group", priority: "1" do
        get discussions_page
        expect_new_page_load { f("#add_discussion").click }
        # This creates the discussion and also tests its creation
        edit_topic("from a student", "tell me a story")
      end

      it "allows group members to access a discussion", :ignore_js_errors, priority: "1" do
        dt = DiscussionTopic.create!(context: @testgroup.first,
                                     user: @teacher,
                                     title: "Discussion Topic",
                                     message: "hi dudes")
        get discussions_page
        # Verifies group member can access the teacher's group discussion & that it's the correct discussion
        expect_new_page_load { f("[data-testid='discussion-link-#{dt.id}']").click }
        expect(f('[data-resource-type="discussion_topic.body"]')).to include_text(dt.message)
      end

      it "has two options when creating a discussion", priority: "1" do
        get discussions_page
        expect_new_page_load { f("#add_discussion").click }
        expect(f('[name="allow_rating"]')).to be_present
        expect(f('[name="allow_todo_date"]')).to be_present
        # Shouldn't be Enable Podcast Feed option
        expect(f("#content")).not_to contain_css('[name="podcast_enabled"]')
      end

      it "only allows group members to access discussions", priority: "1" do
        get discussions_page
        expect(f("#add_discussion")).to be_displayed
        verify_no_course_user_access(discussions_page)
      end

      it "allows discussions to be deleted by their creator", :ignore_js_errors, priority: "1" do
        dt = DiscussionTopic.create!(context: @testgroup.first, user: @user, title: "Delete Me", message: "Discussion text")
        get discussions_page
        expect(f("[data-testid='discussion-link-#{dt.id}']")).to be_truthy
        f(".discussions-index-manage-menu").click
        wait_for_animations
        f("#delete-discussion-menu-option").click
        f("#confirm_delete_discussions").click
        wait_for_ajaximations
        expect(f(".discussions-container__wrapper")).not_to contain_css("[data-testid='discussion-link-#{dt.id}']")
      end

      it "is not able to delete a discussion by a different creator", priority: "1" do
        dt = DiscussionTopic.create!(context: @testgroup.first,
                                     user: @students.first,
                                     title: "Back to the Future day",
                                     message: "There are no hover boards!")
        get discussions_page
        expect(f("[data-testid='discussion-link-#{dt.id}']")).to be_truthy
        expect(f(".discussions-container__wrapper")).not_to contain_css("#discussions-index-manage-menu")
      end

      it "allows group members to edit their discussions", :ignore_js_errors, priority: "1" do
        dt = DiscussionTopic.create!(context: @testgroup.first,
                                     user: @user,
                                     title: "White Snow",
                                     message: "Where are my skis?")
        get discussions_page
        expect_new_page_load { f("[data-testid='discussion-link-#{dt.id}']").click }
        f('[data-testid="discussion-post-menu-trigger"]').click
        expect_new_page_load { f('[data-testid="discussion-thread-menuitem-edit"]').click }
        expect(driver.title).to eq "Edit Discussion Topic"
        edit_topic(dt.title, "The slopes are ready,")
        expect(f('[data-resource-type="discussion_topic.body"]')).to include_text("The slopes are ready,")
      end

      it "does not allow group member to edit discussions by other creators", :ignore_js_errors, priority: "1" do
        dt = DiscussionTopic.create!(context: @testgroup.first,
                                     user: @students.first,
                                     title: "White Snow",
                                     message: "Where are my skis?")
        get discussions_page
        expect_new_page_load { f("[data-testid='discussion-link-#{dt.id}']").click }
        f('[data-testid="discussion-post-menu-trigger"]').click
        expect(f('[data-position-content="discussion-post-menu"]')).not_to contain_css('[data-testid="discussion-thread-menuitem-edit"]')
      end
    end

    #-------------------------------------------------------------------------------------------------------------------
    # We have the funky indenting here because we will remove this once the granular
    # permission stuff is released, and I don't want to complicate the git history
    # for this file
    RSpec.shared_examples "group_pages_student_granular_permissions" do
      describe "pages page" do
        it_behaves_like "pages_page", :student

        it "allows group members to create a page", priority: "1" do
          skip_if_firefox("known issue with firefox https://bugzilla.mozilla.org/show_bug.cgi?id=1335085")
          get pages_page
          manually_create_wiki_page("yo", "this be a page")
        end

        it "allows all group members to access a page", priority: "1" do
          @page = @testgroup.first.wiki_pages.create!(title: "Page", user: @teacher)
          # Verifying with a few different group members should be enough to ensure all group members can see it
          verify_member_sees_group_page

          user_session(@students.first)
          verify_member_sees_group_page
        end

        it "only allows group members to access pages", priority: "1" do
          get pages_page
          expect(f(".new_page")).to be_displayed
          verify_no_course_user_access(pages_page)
        end
      end
    end

    describe "With granular permissions" do
      it_behaves_like "group_pages_student_granular_permissions"
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "Files page on old UI" do
      before(:once) do
        Account.site_admin.enable_feature! :files_a11y_rewrite
        Account.site_admin.enable_feature! :files_a11y_rewrite_toggle
      end

      before do
        @student.set_preference(:files_ui_version, "v1")
      end

      it_behaves_like "files_page_old_ui", :student

      it "only allows group members to access files", priority: "1" do
        get files_page
        verify_no_course_user_access(files_page)
      end
    end

    describe "Files page on files rewrite UI" do
      before(:once) do
        Account.site_admin.enable_feature! :files_a11y_rewrite
        Account.site_admin.enable_feature! :files_a11y_rewrite_toggle
      end

      before do
        @student.set_preference(:files_ui_version, "v2")
      end

      it_behaves_like "files_page_files_rewrite_ui", :student

      it "only allows group members to access files on new files UI", priority: "1" do
        get files_page
        verify_no_course_user_access(files_page)
      end
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "conferences page" do
      before :once do
        PluginSetting.create!(name: "wimba", settings: { "domain" => "wimba.instructure.com" })
      end

      it_behaves_like "conferences_page", :student

      it "allows access to conferences only within the scope of a group", priority: "1" do
        get conferences_page
        expect(f(".new-conference-btn")).to be_displayed
        verify_no_course_user_access(conferences_page)
      end

      it "does not allow inviting users with inactive enrollments" do
        inactive_student = @students.first
        inactive_student.update_attribute(:name, "inactivee")
        inactive_student.enrollments.first.deactivate
        active_student = @students.last
        active_student.update_attribute(:name, "imsoactive")

        get conferences_page

        # create a new conference
        f(".new-conference-btn").click
        wait_for_new_page_load { f("button[data-testid='submit-button']").click }

        new_conference = WebConference.last
        expect(new_conference.users).not_to include(inactive_student)
      end
    end
    #-------------------------------------------------------------------------------------------------------------------

    describe "collaborations page" do
      before do
        setup_google_drive
        unless PluginSetting.where(name: "google_drive").exists?
          PluginSetting.create!(name: "google_drive", settings: {})
        end
      end

      it "lets student in group create a collaboration", priority: "1" do
        get collaborations_page
        replace_content(find("#collaboration_title"), "c1")
        replace_content(find("#collaboration_description"), "c1 description")
        fj('.available-users li:contains("1, Test Student") .icon-user').click
        fj('.btn:contains("Start Collaborating")').click
        # verifies collaboration will be displayed on main window
        tab1 = driver.window_handles.first
        driver.switch_to.window(tab1)
        expect(fj('.collaboration .title:contains("c1")')).to be_present
        expect(fj('.collaboration .description:contains("c1 description")')).to be_present
      end

      it "can invite people within your group", priority: "1" do
        students_in_group = @students
        seed_students(2, "non-group student")
        get collaborations_page
        students_in_group.each do |student|
          expect(fj(".available-users li:contains(#{student.sortable_name}) .icon-user")).to be_present
        end
      end

      it "cannot invite people not in your group", priority: "1" do
        # overriding '@students' array with new students not included in the group
        seed_students(2, "non-group Student")
        get collaborations_page
        users = f(".available-users")
        @students.each do |student|
          expect(users).not_to contain_jqcss("li:contains(#{student.sortable_name}) .icon-user")
        end
      end

      it "cannot invite students with inactive enrollments" do
        inactive_student = @students.first
        inactive_student.update_attribute(:name, "inactivee")
        inactive_student.enrollments.first.deactivate

        get collaborations_page
        expect(f(".available-users")).not_to contain_jqcss("li:contains(#{inactive_student.sortable_name}) .icon-user")
      end

      it "only allows group members to access the group collaborations page", priority: "1" do
        get collaborations_page
        expect(find("#breadcrumbs").text).to include("Collaborations")
        verify_no_course_user_access(collaborations_page)
      end
    end
  end
end
