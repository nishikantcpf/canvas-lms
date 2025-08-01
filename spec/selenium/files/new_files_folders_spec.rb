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
require_relative "../helpers/files_common"

describe "better_file_browsing, folders" do
  include_context "in-process server selenium tests"
  include FilesCommon

  context "Folders" do
    before do
      course_with_teacher_logged_in
      @teacher.set_preference(:files_ui_version, "v1")
      get "/courses/#{@course.id}/files"
      folder_name = "new test folder"
      add_folder(folder_name)
    end

    it "displays the new folder form", priority: "1", upgrade_files_v2: "done" do
      click_new_folder_button
      expect(f("form.ef-edit-name-form")).to be_displayed
    end

    it "creates a new folder", :xbrowser, priority: "1", upgrade_files_v2: "done" do
      # locator was changed from fln in this test due to an issue with edgedriver
      # We can not use fln here
      expect(fj("a:contains('new test folder')")).to be_present
    end

    it "displays all cog icon options", priority: "1", upgrade_files_v2: "done" do
      expect(fj("a:contains('new test folder')")).to be_present
      ff(".ef-item-row").first.click # ensure folder item has focus
      f("button.al-trigger.btn-link").click # toggle cog menu button
      wait_for_animations
      expect(fln("Download")).to be_displayed
      expect(fln("Rename")).to be_displayed
      expect(fln("Move To...")).to be_displayed
      expect(fln("Delete")).to be_displayed
    end

    it "edits folder name", priority: "1", upgrade_files_v2: "done" do
      folder_rename_to = "test folder"
      edit_name_from_cog_icon(folder_rename_to)
      wait_for_ajaximations
      expect(f("#content")).not_to contain_link("new test folder")
      expect(fln("test folder")).to be_present
    end

    it "validates xss on folder text", priority: "1", upgrade_files_v2: "done" do
      add_folder('<script>alert("Hi");</script>')
      expect(ff(".ef-name-col__text")[0].text).to eq '<script>alert("Hi");<_script>'
    end

    it "moves a folder", priority: "1", upgrade_files_v2: "done" do
      ff(".ef-name-col__text")[0].click
      wait_for_ajaximations
      add_folder("test folder")
      move("test folder", 0, :cog_icon)
      wait_for_ajaximations
      expect(f("#flash_message_holder").text).to eq "test folder moved to course files"
      get "/courses/#{@course.id}/files"
      expect(ff(".treeLabel span")[2].text).to eq "test folder"
    end

    it "deletes a folder from cog icon", priority: "1", upgrade_files_v2: "done" do
      skip_if_safari(:alert)
      delete_file(0, :cog_icon)
      expect(f("#content")).not_to contain_link("new test folder")
    end

    it "unpublishes and publish a folder from cloud icon", priority: "1", upgrade_files_v2: "waiting for deployment" do
      set_item_permissions(:unpublish, :cloud_icon)
      expect(f(".btn-link.published-status.unpublished")).to be_displayed
      set_item_permissions(:publish, :cloud_icon)
      expect(f(".btn-link.published-status.published")).to be_displayed
    end

    it "makes folder available to student with link", priority: "1", upgrade_files_v2: "waiting for deployment" do
      set_item_permissions(:restricted_access, :available_with_link, :cloud_icon)
      expect(f(".btn-link.published-status.hiddenState")).to be_displayed
    end

    it "makes folder available to student within given timeframe", priority: "1", upgrade_files_v2: "waiting for deployment" do
      set_item_permissions(:restricted_access, :available_with_timeline, :cloud_icon)
      expect(f(".btn-link.published-status.restricted")).to be_displayed
    end

    it "deletes folder from toolbar", priority: "1", upgrade_files_v2: "done" do
      skip_if_safari(:alert)
      delete_file(0, :toolbar_menu)
      expect(f("body")).not_to contain_css(".ef-item-row")
    end

    it "is able to create and view a new folder with uri characters", priority: "2", upgrade_files_v2: "done" do
      folder_name = "this#could+be bad? maybe"
      add_folder(folder_name)
      folder = @course.folders.where(name: folder_name).first
      expect(folder).to_not be_nil
      file_name = "some silly file"
      @course.attachments.create!(display_name: file_name, uploaded_data: default_uploaded_data, folder:)
      folder_link = fln(folder_name, f(".ef-directory"))
      expect(folder_link).to be_present
      folder_link.click
      wait_for_ajaximations
      # we should be viewing the new folders contents
      file_link = fln(file_name, f(".ef-directory"))
      expect(file_link).to be_present
    end
  end

  context "Folder Tree" do
    before do
      course_with_teacher_logged_in
      @teacher.set_preference(:files_ui_version, "v1")
      get "/courses/#{@course.id}/files"
    end

    it "creates a new folder", priority: "2", upgrade_files_v2: "done" do
      new_folder = create_new_folder
      expect(all_files_folders.count).to eq 1
      expect(new_folder.text).to match(/New Folder/)
    end

    it "handles duplicate folder names", priority: "1", upgrade_files_v2: "done" do
      create_new_folder
      add_folder("New Folder")
      expect(all_files_folders.last.text).to match(/New Folder 2/)
    end

    it "displays folders in tree view", priority: "1", upgrade_files_v2: "feature not included" do
      add_file(fixture_file_upload("example.pdf", "application/pdf"),
               @course,
               "example.pdf")
      get "/courses/#{@course.id}/files"
      create_new_folder
      add_folder("New Folder")
      ff(".ef-name-col__text")[1].click
      wait_for_ajaximations
      add_folder("New Folder 1.1")
      ff(".icon-folder")[1].click
      expect(ff(".ef-name-col__text")[0].text).to eq "New Folder 1.1"
      get "/courses/#{@course.id}/files"
      expect(ff(".ef-name-col__text")[0].text).to eq "example.pdf"
      expect(f(".ef-folder-content")).to be_displayed
    end

    it "creates 15 new child folders and show them in the FolderTree when expanded", priority: "2", upgrade_files_v2: "feature not included" do
      create_new_folder
      f(".ef-name-col > a.ef-name-col__link").click
      wait_for_ajaximations
      1.upto(15) do |number_of_folders|
        folder_regex = (number_of_folders > 1) ? Regexp.new("New Folder\\s#{number_of_folders}") : "New Folder"
        create_new_folder
        expect(all_files_folders.count).to eq number_of_folders
        expect(all_files_folders.last.text).to match folder_regex
      end
      get "/courses/#{@course.id}/files"
      wait_for_ajaximations
      f(".ef-name-col > a.ef-name-col__link").click
      wait_for_ajaximations
      expect(ff("ul.collectionViewItems > li > ul.treeContents > li.subtrees > ul.collectionViewItems li")).to have_size(15)
    end
  end
end
