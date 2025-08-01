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
require_relative "../helpers/groups_common"
require_relative "../helpers/legacy_announcements_common"
require_relative "../helpers/discussions_common"
require_relative "../helpers/wiki_and_tiny_common"
require_relative "../helpers/files_common"
require_relative "../helpers/conferences_common"
require_relative "../helpers/course_common"
require_relative "../helpers/groups_shared_examples"
require_relative "../files_v2/pages/files_page"

describe "groups" do
  include_context "in-process server selenium tests"
  include AnnouncementsCommon
  include ConferencesCommon
  include CourseCommon
  include DiscussionsCommon
  include FilesCommon
  include GroupsCommon
  include WikiAndTinyCommon
  include FilesPage
  setup_group_page_urls

  context "as a teacher" do
    before :once do
      @course = course_model.tap(&:offer!)
      @teacher = teacher_in_course(course: @course, name: "teacher", active_all: true).user
      group_test_setup(4, 1, 1)
      # adds all students to the group
      add_users_to_group(@students, @testgroup.first)
    end

    before do
      user_session(@teacher)
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "home page" do
      it_behaves_like "home_page", :teacher
    end

    describe "announcements page v2" do
      it_behaves_like "announcements_page_v2", :teacher

      it "allows teachers to see announcements" do
        @announcement = @testgroup.first.announcements.create!(
          title: "Group Announcement",
          message: "Group",
          user: @students.first
        )
        AnnouncementIndex.visit_groups_index(@testgroup.first)
        expect(ff(".ic-announcement-row").size).to eq 1
      end

      it "allows teachers to create an announcement" do
        # Checks that initial user can create an announcement
        AnnouncementNewEdit.create_group_announcement(@testgroup.first,
                                                      "Announcement by #{@teacher.name}",
                                                      "sup")
        get announcements_page
        expect(ff(".ic-announcement-row").size).to eq 1
      end

      it "allows teachers to delete their own group announcements" do
        skip_if_safari(:alert)
        @testgroup.first.announcements.create!(
          title: "Student Announcement",
          message: "test message",
          user: @teacher
        )

        get announcements_page
        expect(ff(".ic-announcement-row").size).to eq 1
        AnnouncementIndex.delete_announcement_manually("Student Announcement")
        expect(f(".announcements-v2__wrapper")).not_to contain_css(".ic-announcement-row")
      end

      it "allows teachers to delete group member announcements" do
        skip_if_safari(:alert)
        @testgroup.first.announcements.create!(
          title: "Student Announcement",
          message: "test message",
          user:
          @students.first
        )

        get announcements_page
        expect(ff(".ic-announcement-row").size).to eq 1
        AnnouncementIndex.delete_announcement_manually("Student Announcement")
        expect(f(".announcements-v2__wrapper")).not_to contain_css(".ic-announcement-row")
      end

      it "lets teachers see announcement details", :ignore_js_errors do
        announcement = @testgroup.first.announcements.create!(
          title: "Test Announcement",
          message: "test message",
          user: @teacher
        )
        get announcements_page
        expect_new_page_load { AnnouncementIndex.click_on_announcement(announcement.title) }
        expect(f('[data-testid="message_title"]')).to include_text("Test Announcement")
        expect(f('[data-resource-type="announcement.body"]').text).to eq "test message"
      end

      it "edit button from announcement details works on teachers announcement" do
        announcement = @testgroup.first.announcements.create!(
          title: "Test Announcement",
          message: "test message",
          user: @teacher
        )
        url_base = AnnouncementNewEdit.full_individual_announcement_url(
          @testgroup.first,
          announcement
        )
        get url_base
        f('[data-testid="discussion-post-menu-trigger"]').click
        expect_new_page_load { f('[data-testid="discussion-thread-menuitem-edit"]').click }
        expect(driver.current_url).to include "#{url_base}/edit"
        expect(f("#content-wrapper")).not_to contain_css("#sections_autocomplete_root input")
      end

      it "edit page should succeed for their own announcements" do
        announcement = @testgroup.first.announcements.create!(
          title: "Announcement by #{@user.name}",
          message: "The Force Awakens",
          user: @teacher
        )
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

      it "lets teachers edit group member announcements" do
        announcement = @testgroup.first.announcements.create!(
          title: "Your Announcement",
          message: "test message",
          user: @students.first
        )
        url_base = AnnouncementNewEdit.full_individual_announcement_url(
          @testgroup.first,
          announcement
        )
        get url_base
        f('[data-testid="discussion-post-menu-trigger"]').click
        expect_new_page_load { f('[data-testid="discussion-thread-menuitem-edit"]').click }
        expect(driver.current_url).to include "#{url_base}/edit"
        expect(f("#content-wrapper")).not_to contain_css("#sections_autocomplete_root input")
      end

      it "edit page should succeed for group member announcements" do
        announcement = @testgroup.first.announcements.create!(
          title: "Announcement by #{@user.name}",
          message: "The Force Awakens",
          user: @students.first
        )
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
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "people page" do
      it_behaves_like "people_page", :teacher

      it "displays and show a list of group members", priority: "2" do
        get people_page
        # Checks that all students and teachers created in setup are listed on page
        expect(ff(".student_roster .user_name").size).to eq 4
        expect(ff(".teacher_roster .user_name").size).to eq 2
      end

      it "shows both active and inactive members in groups to teachers", priority: "2" do
        get people_page
        expect(ff(".student_roster .user_name").size).to eq 4
        student_enrollment = StudentEnrollment.last
        student_enrollment.workflow_state = "inactive"
        student_enrollment.save!
        refresh_page
        expect(ff(".student_roster .user_name").size).to eq 4
      end
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "discussions page" do
      it_behaves_like "discussions_page", :teacher

      it "allows teachers to create discussions within a group", priority: "1" do
        get discussions_page
        expect_new_page_load { f("#add_discussion").click }
        # This creates the discussion and also tests its creation
        edit_topic("from a teacher", "tell me a story")
      end

      it "has three options when creating a discussion", priority: "1" do
        get discussions_page
        expect_new_page_load { f("#add_discussion").click }
        expect(f('[name="allow_rating"]')).to be_present
        expect(f('[name="allow_todo_date"]')).to be_present
        expect(f('[name="podcast_enabled"]')).to be_present
      end

      it "allows teachers to access a discussion", :ignore_js_errors, priority: "1" do
        dt = DiscussionTopic.create!(context: @testgroup.first,
                                     user: @students.first,
                                     title: "Discussion Topic",
                                     message: "hi dudes")
        get discussions_page
        # Verifies teacher can access the group discussion & that it's the correct discussion
        expect_new_page_load { f("[data-testid='discussion-link-#{dt.id}']").click }
        expect(f('[data-resource-type="discussion_topic.body"]')).to include_text(dt.message)
      end

      it "allows teachers to delete their group discussions", :ignore_js_errors, priority: "1" do
        skip_if_safari(:alert)
        dt = DiscussionTopic.create!(context: @testgroup.first,
                                     user: @teacher,
                                     title: "Group Discussion",
                                     message: "Group")
        get discussions_page
        expect(f("[data-testid='discussion-link-#{dt.id}']")).to be_truthy
        f(".discussions-index-manage-menu").click
        wait_for_animations
        f("#delete-discussion-menu-option").click
        wait_for_ajaximations
        f("#confirm_delete_discussions").click
        wait_for_ajaximations
        expect(f(".discussions-container__wrapper")).not_to contain_css("[data-testid='discussion-link-#{dt.id}']")
      end
    end

    #-------------------------------------------------------------------------------------------------------------------
    # We have the funky indenting here because we will remove this once the granular
    # permission stuff is released, and I don't want to complicate the git history
    # for this file
    RSpec.shared_examples "group_pages_teacher_granular_permissions" do
      describe "pages page" do
        it_behaves_like "pages_page", :teacher

        it "allows teachers to create a page", priority: "1" do
          skip_if_firefox("known issue with firefox https://bugzilla.mozilla.org/show_bug.cgi?id=1335085")
          get pages_page
          manually_create_wiki_page("stuff", "it happens")
        end

        it "allows teachers to access a page", priority: "1" do
          @page = @testgroup.first.wiki_pages.create!(title: "Page", user: @students.first)
          # Verifies teacher can access the group page & that it's the correct page
          verify_member_sees_group_page
        end

        it "has unique pages in the cloned groups", priority: "2" do
          @page = @testgroup.first.wiki_pages.create!(title: "Page", user: @students.first)
          get pages_page
          expect(f(".index-content")).to contain_css(".wiki-page-link")

          category = @course.group_categories.create!(name: "Group Category")
          @group_category.first.clone_groups_and_memberships(category)
          category.reload
          new_group = category.groups.first

          get "/groups/#{new_group.id}/pages"
          expect(f(".index-content")).not_to contain_css(".wiki-page-link")
        end
      end
    end

    describe "With granular permission on" do
      it_behaves_like "group_pages_teacher_granular_permissions"
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "Files page on old UI" do
      before(:once) do
        Account.site_admin.enable_feature! :files_a11y_rewrite
        Account.site_admin.enable_feature! :files_a11y_rewrite_toggle
      end

      before do
        @teacher.set_preference(:files_ui_version, "v1")
      end

      it_behaves_like "files_page_old_ui", :teacher
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "Files page on files rewrite UI" do
      before(:once) do
        Account.site_admin.enable_feature! :files_a11y_rewrite
        Account.site_admin.enable_feature! :files_a11y_rewrite_toggle
      end

      before do
        @teacher.set_preference(:files_ui_version, "v2")
      end

      it_behaves_like "files_page_files_rewrite_ui", :teacher
    end

    #-------------------------------------------------------------------------------------------------------------------
    describe "conferences page" do
      before(:once) do
        PluginSetting.create!(name: "wimba", settings: { "domain" => "wimba.instructure.com" })
      end

      it_behaves_like "conferences_page", :teacher
    end
  end
end
