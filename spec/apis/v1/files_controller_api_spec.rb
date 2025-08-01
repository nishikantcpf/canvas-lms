# frozen_string_literal: true

#
# Copyright (C) 2011 Instructure, Inc.
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
#

require_relative "../api_spec_helper"
require_relative "../locked_examples"
require "webmock/rspec"

RSpec.configure do |config|
  config.include ApplicationHelper
end

describe "Files API", type: :request do
  before :once do
    course_with_teacher(active_all: true, user: user_with_pseudonym)
  end

  context "locked api item" do
    let(:item_type) { "file" }

    let(:locked_item) do
      root_folder = Folder.root_folders(@course).first
      Attachment.create!(filename: "test.png", display_name: "test-frd.png", uploaded_data: stub_png_data, folder: root_folder, context: @course)
    end

    def api_get_json
      api_call(
        :get,
        "/api/v1/files/#{locked_item.id}",
        { controller: "files", action: "api_show", format: "json", id: locked_item.id.to_s }
      )
    end

    include_examples "a locked api item"
  end

  describe "create file" do
    def call_course_create_file
      api_call(:post, "/api/v1/courses/#{@course.id}/files", {
                 controller: "courses",
                 action: "create_file",
                 course_id: @course.id,
                 format: "json",
                 name: "test_file.png",
                 size: "12345",
                 content_type: "image/png",
                 success_include: ["avatar"],
                 no_redirect: "true"
               })
    end

    it "includes success_include param in file create url" do
      local_storage!
      json = call_course_create_file
      query = Rack::Utils.parse_nested_query(URI(json["upload_url"]).query)
      expect(query["success_include"]).to include("avatar")
    end

    it "includes include param in create success url" do
      s3_storage!
      json = call_course_create_file
      query = Rack::Utils.parse_nested_query(URI(json["upload_params"]["success_url"]).query)
      expect(query["include"]).to include("avatar")
    end

    it "includes include capture param in inst_fs token" do
      secret = "secret"
      allow(InstFS).to receive_messages(enabled?: true, jwt_secrets: [secret])
      json = call_course_create_file
      query = Rack::Utils.parse_nested_query(URI(json["upload_url"]).query)
      payload = Canvas::Security.decode_jwt(query["token"], [secret])
      expect(payload["capture_params"]["include"]).to include("avatar")
    end

    context "as teacher having manage_files_add permission" do
      it "creates a course file" do
        api_call(
          :post,
          "/api/v1/courses/#{@course.id}/files",
          {
            controller: "courses",
            action: "create_file",
            course_id: @course.id,
            format: "json",
            name: "test_file.png",
            size: "12345",
            content_type: "image/png",
            success_include: ["avatar"],
            no_redirect: "true"
          },
          {},
          expected_status: 200
        )
      end
    end

    context "as teacher without manage_files_add permission" do
      before do
        teacher_role = Role.get_built_in_role("TeacherEnrollment", root_account_id: @course.root_account.id)
        RoleOverride.create!(
          permission: "manage_files_add",
          enabled: false,
          role: teacher_role,
          account: @course.root_account
        )
      end

      it "disallows creating a course file" do
        api_call(
          :post,
          "/api/v1/courses/#{@course.id}/files",
          {
            controller: "courses",
            action: "create_file",
            course_id: @course.id,
            format: "json",
            name: "test_file.png",
            size: "12345",
            content_type: "image/png",
            success_include: ["avatar"],
            no_redirect: "true"
          },
          {},
          expected_status: 401
        )
      end
    end

    context "in a canvas career course" do
      before :once do
        account = @course.account
        account.enable_feature!(:horizon_course_setting)
        @course.update horizon_course: true
      end

      it "allows setting estimated duration" do
        api_call(
          :post,
          "/api/v1/courses/#{@course.id}/files",
          {
            controller: "courses",
            action: "create_file",
            course_id: @course.id,
            format: "json",
            name: "test_file.png",
            size: "12345",
            content_type: "image/png",
            no_redirect: "true",
            estimated_duration_attributes: { minutes: 5 }
          },
          {},
          expected_status: 200
        )
        expect(Attachment.last.estimated_duration.duration).to eq 5.minutes
      end
    end

    context "as student" do
      before do
        course_with_student_logged_in(course: @course)
      end

      it "returns unauthorized error" do
        api_call(
          :post,
          "/api/v1/courses/#{@course.id}/files",
          {
            controller: "courses",
            action: "create_file",
            course_id: @course.id,
            format: "json",
            name: "test_file.png",
            size: "12345",
            content_type: "image/png",
            success_include: ["avatar"],
            no_redirect: "true"
          },
          {},
          expected_status: 401
        )
      end
    end
  end

  describe "api_create" do
    it "includes success_include as include when redirecting" do
      local_storage!
      file = Rack::Test::UploadedFile.new(file_fixture("a_file.txt"), "")
      a = attachment_model(workflow_state: :unattached)
      params = a.ajax_upload_params("/url", "/s3")[:upload_params]
      raw_api_call(:post,
                   "/files_api",
                   params.merge({
                                  controller: "files",
                                  action: "api_create",
                                  success_include: ["avatar"],
                                  file:
                                }))
      expect(redirect_params["include"]).to include("avatar")
    end
  end

  describe "api_create_success" do
    before :once do
      @attachment = Attachment.new
      @attachment.context = @course
      @attachment.filename = "test.txt"
      @attachment.file_state = "deleted"
      @attachment.workflow_state = "unattached"
      @attachment.content_type = "text/plain"
      @attachment.save!
    end

    def upload_data
      @attachment.workflow_state = nil
      @content = Tempfile.new(["test", ".txt"])
      def @content.content_type # rubocop:disable Lint/NestedMethodDefinition
        "text/plain"
      end
      @content.write("test file")
      @content.rewind
      @attachment.uploaded_data = @content
      @attachment.save!
    end

    def call_create_success(params = {})
      api_call(
        :post,
        "/api/v1/files/#{@attachment.id}/create_success?uuid=#{@attachment.uuid}",
        params.merge({
                       controller: "files",
                       action: "api_create_success",
                       format: "json",
                       id: @attachment.to_param,
                       uuid: @attachment.uuid
                     })
      )
    end

    double_testing_with_disable_adding_uuid_verifier_in_api_ff do
      it "sets the attachment to available (local storage)" do
        local_storage!
        upload_data
        json = call_create_success
        @attachment.reload
        expect(json).to eq({
                             "id" => @attachment.id,
                             "folder_id" => @attachment.folder_id,
                             "url" => file_download_url(@attachment, verifier: (@attachment.uuid unless disable_adding_uuid_verifier_in_api), download: "1", download_frd: "1"),
                             "content-type" => "text/plain",
                             "display_name" => "test.txt",
                             "filename" => @attachment.filename,
                             "size" => @attachment.size,
                             "unlock_at" => nil,
                             "locked" => false,
                             "hidden" => false,
                             "lock_at" => nil,
                             "locked_for_user" => false,
                             "preview_url" => context_url(@attachment.context, :context_file_file_preview_url, @attachment, annotate: 0),
                             "hidden_for_user" => false,
                             "created_at" => @attachment.created_at.as_json,
                             "updated_at" => @attachment.updated_at.as_json,
                             "upload_status" => "success",
                             "thumbnail_url" => nil,
                             "modified_at" => @attachment.modified_at.as_json,
                             "mime_class" => @attachment.mime_class,
                             "media_entry_id" => @attachment.media_entry_id,
                             "canvadoc_session_url" => nil,
                             "crocodoc_session_url" => nil,
                             "category" => "uncategorized",
                             "visibility_level" => @attachment.visibility_level
                           })
        expect(@attachment.file_state).to eq "available"
      end

      it "sets the attachment to available (s3 storage)" do
        s3_storage!

        expect_any_instance_of(Aws::S3::Object).to receive(:data).and_return({
                                                                               content_type: "text/plain",
                                                                               content_length: 1234,
                                                                             })

        json = call_create_success
        @attachment.reload
        file_download_url(@attachment, verifier: @attachment.uuid, download: "1", download_frd: "1")
        expect(json).to eq({
                             "id" => @attachment.id,
                             "folder_id" => @attachment.folder_id,
                             "url" => file_download_url(@attachment, verifier: (@attachment.uuid unless disable_adding_uuid_verifier_in_api), download: "1", download_frd: "1"),
                             "content-type" => "text/plain",
                             "display_name" => "test.txt",
                             "filename" => @attachment.filename,
                             "size" => @attachment.size,
                             "unlock_at" => nil,
                             "locked" => false,
                             "hidden" => false,
                             "lock_at" => nil,
                             "locked_for_user" => false,
                             "preview_url" => context_url(@attachment.context, :context_file_file_preview_url, @attachment, annotate: 0),
                             "hidden_for_user" => false,
                             "created_at" => @attachment.created_at.as_json,
                             "updated_at" => @attachment.updated_at.as_json,
                             "upload_status" => "success",
                             "thumbnail_url" => nil,
                             "modified_at" => @attachment.modified_at.as_json,
                             "mime_class" => @attachment.mime_class,
                             "media_entry_id" => @attachment.media_entry_id,
                             "canvadoc_session_url" => nil,
                             "crocodoc_session_url" => nil,
                             "category" => "uncategorized",
                             "visibility_level" => @attachment.visibility_level
                           })
        expect(@attachment.reload.file_state).to eq "available"
      end
    end

    it "includes usage rights if overwriting a file that has them already" do
      local_storage!
      usage_rights = @course.usage_rights.create! use_justification: "creative_commons", legal_copyright: "(C) 2014 XYZ Corp", license: "cc_by_nd"
      @attachment.usage_rights = usage_rights
      @attachment.save!
      upload_data
      json = call_create_success
      expect(json["usage_rights"]).to eq({ "use_justification" => "creative_commons",
                                           "license" => "cc_by_nd",
                                           "legal_copyright" => "(C) 2014 XYZ Corp",
                                           "license_name" => "CC Attribution No Derivatives" })
    end

    it "stores long-ish non-ASCII filenames (local storage)" do
      local_storage!
      @attachment.update_attribute(:filename, "Качество образования-1.txt")
      upload_data
      expect { call_create_success }.not_to raise_error
      expect(@attachment.reload.open.read).to eq "test file"
    end

    it "renders the response as application/json with no verifiers when in app" do
      s3_storage!
      allow_any_instance_of(FilesController).to receive(:in_app?).and_return(true)
      allow_any_instance_of(FilesController).to receive(:verified_request?).and_return(true)

      expect_any_instance_of(Aws::S3::Object).to receive(:data).and_return({
                                                                             content_type: "text/plain",
                                                                             content_length: 1234,
                                                                           })

      raw_api_call(:post,
                   "/api/v1/files/#{@attachment.id}/create_success?uuid=#{@attachment.uuid}",
                   { controller: "files", action: "api_create_success", format: "json", id: @attachment.to_param, uuid: @attachment.uuid })
      expect(response.headers[content_type_key]).to eq "application/json; charset=utf-8"
      expect(response.body).not_to include "verifier="
    end

    it "fails for an incorrect uuid" do
      upload_data
      raw_api_call(:post,
                   "/api/v1/files/#{@attachment.id}/create_success?uuid=abcde",
                   { controller: "files", action: "api_create_success", format: "json", id: @attachment.to_param, uuid: "abcde" })
      assert_status(400)
    end

    it "fails if the attachment is already available" do
      upload_data
      @attachment.update_attribute(:file_state, "available")
      raw_api_call(:post,
                   "/api/v1/files/#{@attachment.id}/create_success?uuid=#{@attachment.uuid}",
                   { controller: "files", action: "api_create_success", format: "json", id: @attachment.to_param, uuid: @attachment.uuid })
      assert_status(400)
    end

    it "includes canvadoc preview url if requested and available" do
      allow(Canvadocs).to receive(:enabled?).and_return(true)
      allow(Canvadoc).to receive(:mime_types).and_return([@attachment.content_type])
      local_storage!
      upload_data
      json = call_create_success(include: ["preview_url"])
      expect(json["preview_url"]).to include("/api/v1/canvadoc_session")
    end

    it "includes nil preview url if requested and not available" do
      allow(Canvadocs).to receive(:enabled?).and_return(false)
      allow(Canvadoc).to receive(:mime_types).and_return([])
      local_storage!
      upload_data
      json = call_create_success(include: ["preview_url"])
      expect(json["preview_url"]).to be_nil
    end

    context "upload success context callback" do
      before do
        allow_any_instance_of(Course).to receive(:file_upload_success_callback)
        expect_any_instance_of(Course).to receive(:file_upload_success_callback).with(@attachment)
      end

      it "calls back for s3" do
        s3_storage!
        expect_any_instance_of(Aws::S3::Object).to receive(:data).and_return({
                                                                               content_type: "text/plain",
                                                                               content_length: 1234,
                                                                             })
        call_create_success
      end

      it "calls back for local storage" do
        local_storage!
        upload_data
        call_create_success
      end
    end
  end

  describe "api_capture" do
    let(:secret) { "secret" }
    let(:jwt) { Canvas::Security.create_jwt({}, nil, secret) }
    let(:folder) { Folder.root_folders(@course).first }
    let(:instfs_uuid) { 123 }

    # default set of params; parts will be overridden per test
    let(:base_params) do
      {
        user_id: @user.id,
        context_type: Course,
        context_id: @course.id,
        size: 2.megabytes,
        name: "test.txt",
        content_type: "text/plain",
        instfs_uuid:,
        quota_exempt: true,
        folder_id: folder.id,
        on_duplicate: "overwrite",
        token: jwt,
      }
    end

    before do
      allow(InstFS).to receive_messages(enabled?: true, jwt_secrets: [secret])
    end

    it "is not available without the InstFS feature" do
      allow(InstFS).to receive(:enabled?).and_return false
      raw_api_call(:post,
                   "/api/v1/files/capture?#{base_params.to_query}",
                   base_params.merge(controller: "files", action: "api_capture", format: "json"))
      assert_status(404)
    end

    it "requires a service JWT to authorize" do
      params = base_params.merge(token: nil)
      raw_api_call(:post,
                   "/api/v1/files/capture?#{params.to_query}",
                   params.merge(controller: "files", action: "api_capture", format: "json"))
      assert_forbidden
    end

    it "checks quota unless exempt" do
      @course.storage_quota = base_params[:size] / 2
      @course.save!
      params = base_params.merge(quota_exempt: false)
      json = api_call(:post,
                      "/api/v1/files/capture?#{params.to_query}",
                      params.merge(controller: "files", action: "api_capture", format: "json"),
                      expected_status: 400)
      expect(json["message"]).to eq "file size exceeds quota limits"
    end

    it "bypasses quota when exempt" do
      @course.storage_quota = base_params[:size] / 2
      @course.save!
      params = base_params.merge(quota_exempt: true)
      raw_api_call(:post,
                   "/api/v1/files/capture?#{params.to_query}",
                   params.merge(controller: "files", action: "api_capture", format: "json"))
      assert_status(201)
    end

    it "creates file locked when usage rights required" do
      @course.usage_rights_required = true
      @course.save!
      api_call(:post,
               "/api/v1/files/capture?#{base_params.to_query}",
               base_params.merge(controller: "files", action: "api_capture", format: "json"))
      attachment = Attachment.where(instfs_uuid:).first
      expect(attachment.locked).to be true
    end

    it "creates file unlocked when usage rights not required" do
      @course.usage_rights_required = false
      @course.save!
      api_call(:post,
               "/api/v1/files/capture?#{base_params.to_query}",
               base_params.merge(controller: "files", action: "api_capture", format: "json"))
      attachment = Attachment.where(instfs_uuid:).first
      expect(attachment.locked).to be false
    end

    it "handle duplicate paths according to on_duplicate" do
      params = base_params.merge(on_duplicate: "overwrite")
      existing = Attachment.create!(
        context: @course,
        folder:,
        uploaded_data: StringIO.new("existing"),
        filename: params[:name],
        display_name: params[:name]
      )
      api_call(:post,
               "/api/v1/files/capture?#{base_params.to_query}",
               base_params.merge(controller: "files", action: "api_capture", format: "json"))
      existing.reload
      attachment = Attachment.where(instfs_uuid:).first
      expect(attachment).not_to eq(existing)
      expect(attachment.display_name).to eq params[:name]
      expect(existing).to be_deleted
      expect(existing.replacement_attachment).to eq attachment
    end

    it "is permitted if attachment context is an account" do
      account = Account.default
      folder = Folder.root_folders(account).first
      params = base_params.merge(context_type: "Account", context_id: account.global_id, folder: folder.id, size: 864.kilobytes)
      raw_api_call(:post,
                   "/api/v1/files/capture?#{params.to_query}",
                   params.merge(controller: "files", action: "api_capture", format: "json"))
      assert_status(201)
    end

    it "fixes broken content_types" do
      params = base_params.merge(name: "file.doc", content_type: "application/x-cfb")
      api_call(:post,
               "/api/v1/files/capture?#{params.to_query}",
               params.merge(controller: "files", action: "api_capture", format: "json"))
      attachment = Attachment.where(instfs_uuid:).first
      expect(attachment.content_type).to eq "application/msword"
    end

    describe "re-uploading a file" do
      before :once do
        @existing = Attachment.create!(
          context: @course,
          folder:,
          uploaded_data: StringIO.new("a file"),
          filename: base_params[:name],
          display_name: base_params[:name],
          instfs_uuid: "old-instfs-uuid"
        )
        @capture_params = base_params.merge(controller: "files",
                                            action: "api_capture",
                                            format: "json",
                                            size: @existing.size,
                                            sha512: @existing.md5,
                                            instfs_uuid: "new-instfs-uuid",
                                            on_duplicate: "overwrite")
      end

      it "reuses the Attachment if a file is re-uploaded to the same folder" do
        expect(InstFS).to receive(:delete_file).with("new-instfs-uuid")
        json = api_call(:post, "/api/v1/files/capture?#{@capture_params.to_query}", @capture_params)
        expect(json["id"]).to eq @existing.id
        expect(@existing.reload.instfs_uuid).to eq "old-instfs-uuid"
      end

      it "does not delete the new instfs file if it is somehow in use by other Attachments" do
        other_course = course_factory
        other_file = @existing.clone_for(other_course)
        other_file.instfs_uuid = "new-instfs-uuid"
        other_file.save!
        expect(InstFS).not_to receive(:delete_file)
        json = api_call(:post, "/api/v1/files/capture?#{@capture_params.to_query}", @capture_params)
        expect(json["id"]).to eq @existing.id
        expect(@existing.reload.instfs_uuid).to eq "old-instfs-uuid"
        expect(other_file.reload.instfs_uuid).to eq "new-instfs-uuid"
      end

      it "does not reuse a deleted Attachment" do
        @existing.destroy
        expect(InstFS).not_to receive(:delete_file)
        json = api_call(:post, "/api/v1/files/capture?#{@capture_params.to_query}", @capture_params)
        expect(json["id"]).not_to eq @existing.id
      end
    end

    it "redirect has preview_url include if requested" do
      raw_api_call(
        :post,
        "/api/v1/files/capture?#{base_params.to_query}",
        base_params.merge(
          controller: "files",
          action: "api_capture",
          format: "json",
          include: ["preview_url"]
        )
      )
      expect(redirect_params["include"]).to include("preview_url")
      expect(redirect_params["include"]).not_to include("enhanced_preview_url")
    end

    it "includes enhanced_preview_url in course context" do
      raw_api_call(
        :post,
        "/api/v1/files/capture?#{base_params.to_query}",
        base_params.merge(
          controller: "files",
          action: "api_capture",
          format: "json"
        )
      )
      expect(redirect_params["include"]).to include("enhanced_preview_url")
    end

    it "includes enhanced_preview_url in group context" do
      group = @course.groups.create!
      params = base_params.merge(context_type: Group, context_id: group.id)
      raw_api_call(
        :post,
        "/api/v1/files/capture?#{params.to_query}",
        params.merge(
          controller: "files",
          action: "api_capture",
          format: "json"
        )
      )
      expect(redirect_params["include"]).to include("enhanced_preview_url")
    end

    context "with 'category' not present in params" do
      subject { Attachment.find_by(instfs_uuid:) }

      let(:category) { "" }
      let(:params) { base_params.merge(category:, controller: "files", action: "api_capture", format: "json") }

      it "uses the default category" do
        raw_api_call(
          :post,
          "/api/v1/files/capture?#{params.to_query}",
          params
        )

        expect(subject.category).to eq "uncategorized"
      end
    end

    context "with 'category' present in params" do
      subject { Attachment.find_by(instfs_uuid:) }

      let(:category) { Attachment::ICON_MAKER_ICONS }
      let(:params) { base_params.merge(category:, controller: "files", action: "api_capture", format: "json") }

      it "sets the attachment category" do
        raw_api_call(
          :post,
          "/api/v1/files/capture?#{params.to_query}",
          params
        )

        expect(subject.category).to eq category
      end
    end
  end

  describe "#index" do
    before :once do
      @root = Folder.root_folders(@course).first
      @f1 = @root.sub_folders.create!(name: "folder1", context: @course)
      @a1 = Attachment.create!(filename: "ztest.txt", display_name: "ztest.txt", position: 1, uploaded_data: StringIO.new("file"), folder: @f1, context: @course)
      @a3 = Attachment.create(filename: "atest3.txt", display_name: "atest3.txt", position: 2, uploaded_data: StringIO.new("file"), folder: @f1, context: @course)
      @a3.hidden = true
      @a3.save!
      @a2 = Attachment.create!(filename: "mtest2.txt", display_name: "mtest2.txt", position: 3, uploaded_data: StringIO.new("file"), folder: @f1, context: @course, locked: true)

      @files_path = "/api/v1/folders/#{@f1.id}/files"
      @files_path_options = { controller: "files", action: "api_index", format: "json", id: @f1.id.to_param }
    end

    double_testing_with_disable_adding_uuid_verifier_in_api_ff(attachment_variable_name: "a1") do
      it "lists files in alphabetical order" do
        json = api_call(:get, @files_path, @files_path_options, {})
        res = json.pluck("display_name")
        expect(res).to eq %w[atest3.txt mtest2.txt ztest.txt]
        json.pluck("url").each { |url| expect(url).to include "verifier=" } unless disable_adding_uuid_verifier_in_api
      end

      it "does not omit verifiers using session auth if params[:use_verifiers] is given" do
        user_session(@user)
        get @files_path + "?use_verifiers=1"
        expect(response).to be_successful
        json = json_parse
        json.pluck("url").each { |url| expect(url).to include "verifier=" } unless disable_adding_uuid_verifier_in_api
      end
    end

    it "omits verifiers using session auth" do
      user_session(@user)
      get @files_path
      expect(response).to be_successful
      json = json_parse
      json.pluck("url").each { |url| expect(url).not_to include "verifier=" }
    end

    it "lists files in saved order if flag set" do
      json = api_call(:get, @files_path + "?sort_by=position", @files_path_options.merge(sort_by: "position"), {})
      res = json.pluck("display_name")
      expect(res).to eq %w[ztest.txt atest3.txt mtest2.txt]
    end

    it "does not list locked file if not authed" do
      course_with_student_logged_in(course: @course)
      json = api_call(:get, @files_path, @files_path_options, {})
      expect(json.any? { |f| f["id"] == @a2.id }).to be_falsey
    end

    it "does not list hidden files if not authed" do
      course_with_student_logged_in(course: @course)
      json = api_call(:get, @files_path, @files_path_options, {})

      expect(json.any? { |f| f["id"] == @a3.id }).to be_falsey
    end

    it "lists hidden files with :read_as_admin rights" do
      course_with_ta(course: @course, active_all: true)
      user_session(@user)
      @course.account.role_overrides.create!(permission: :manage_files_add, enabled: false, role: ta_role)
      json = api_call(:get, @files_path, @files_path_options, {})

      expect(json.any? { |f| f["id"] == @a3.id }).to be_truthy
    end

    it "does not list locked folder if not authed" do
      @f1.locked = true
      @f1.save!
      course_with_student_logged_in(course: @course)
      raw_api_call(:get, @files_path, @files_path_options, {}, {})
      assert_forbidden
    end

    it "404s for no folder found" do
      raw_api_call(:get, "/api/v1/folders/0/files", @files_path_options.merge(id: "0"), {}, {})
      assert_status(404)
    end

    it "paginates" do
      7.times { |i| Attachment.create!(filename: "test#{i}.txt", display_name: "test#{i}.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course) }
      json = api_call(:get, "/api/v1/folders/#{@root.id}/files?per_page=3", @files_path_options.merge(id: @root.id.to_param, per_page: "3"), {})
      expect(json.length).to eq 3
      links = response.headers["Link"].split(",")
      expect(links.all? { |l| l =~ %r{api/v1/folders/#{@root.id}/files} }).to be_truthy
      expect(links.find { |l| l.include?('rel="next"') }).to match(/page=2/)
      expect(links.find { |l| l.include?('rel="first"') }).to match(/page=1/)
      expect(links.find { |l| l.include?('rel="last"') }).to match(/page=3/)

      json = api_call(:get, "/api/v1/folders/#{@root.id}/files?per_page=3&page=3", @files_path_options.merge(id: @root.id.to_param, per_page: "3", page: "3"), {})
      expect(json.length).to eq 1
      links = response.headers["Link"].split(",")
      expect(links.all? { |l| l =~ %r{api/v1/folders/#{@root.id}/files} }).to be_truthy
      expect(links.find { |l| l.include?('rel="prev"') }).to match(/page=2/)
      expect(links.find { |l| l.include?('rel="first"') }).to match(/page=1/)
      expect(links.find { |l| l.include?('rel="last"') }).to match(/page=3/)
    end

    it "only returns names if requested" do
      json = api_call(:get, @files_path, @files_path_options, { only: ["names"] })
      res = json.pluck("display_name")
      expect(res).to eq %w[atest3.txt mtest2.txt ztest.txt]
      expect(json.any? { |f| f["url"] }).to be_falsey
    end

    context "content_types" do
      before :once do
        attachment_model display_name: "thing.png", content_type: "image/png", context: @course, folder: @f1
        attachment_model display_name: "thing.gif", content_type: "image/gif", context: @course, folder: @f1
      end

      it "matches one content-type" do
        json = api_call(:get, @files_path + "?content_types=image", @files_path_options.merge(content_types: "image"), {})
        res = json.pluck("display_name")
        expect(res).to eq %w[thing.gif thing.png]
      end

      it "matches multiple content-types" do
        json = api_call(:get,
                        @files_path + "?content_types[]=text&content_types[]=image/gif",
                        @files_path_options.merge(content_types: ["text", "image/gif"]))
        res = json.pluck("display_name")
        expect(res).to eq %w[atest3.txt mtest2.txt thing.gif ztest.txt]
      end
    end

    it "searches for files by title" do
      atts = []
      2.times { |i| atts << Attachment.create!(filename: "first#{i}.txt", display_name: "first#{i}.txt", uploaded_data: StringIO.new("file"), folder: @f1, context: @course) }
      2.times { |i| Attachment.create!(filename: "second#{i}.txt", display_name: "second#{i}.txt", uploaded_data: StringIO.new("file"), folder: @f1, context: @course) }

      json = api_call(:get, @files_path + "?search_term=fir", @files_path_options.merge(search_term: "fir"), {})
      expect(json.pluck("id").sort).to eq atts.map(&:id).sort
    end

    it "includes user if requested" do
      @a1.update_attribute(:user, @user)
      json = api_call(:get, @files_path + "?include[]=user", @files_path_options.merge(include: ["user"]))
      expect(json.pluck("user")).to eql [
        {},
        {},
        {
          "id" => @user.id,
          "anonymous_id" => @user.id.to_s(36),
          "display_name" => @user.short_name,
          "avatar_image_url" => User.avatar_fallback_url(nil, request),
          "html_url" => "http://www.example.com/courses/#{@course.id}/users/#{@user.id}",
          "pronouns" => nil
        }
      ]
    end

    it "includes usage_rights if requested" do
      @a1.usage_rights = @course.usage_rights.create! legal_copyright: "(C) 2014 Initech", use_justification: "used_by_permission"
      @a1.save!
      json = api_call(:get, @files_path + "?include[]=usage_rights", @files_path_options.merge(include: ["usage_rights"]))
      expect(json.pluck("usage_rights")).to eql [
        nil,
        nil,
        {
          "legal_copyright" => "(C) 2014 Initech",
          "use_justification" => "used_by_permission",
          "license" => "private",
          "license_name" => "Private (Copyrighted)"
        }
      ]
    end

    it "includes an instfs_uuid if ?include[]-ed" do
      json = api_call(:get, @files_path, @files_path_options.merge(include: ["instfs_uuid"]))
      expect(json[0]).to have_key "instfs_uuid"
    end

    context "when the context is a user" do
      subject do
        api_call(:get, request_url, request_params)
      end

      let(:user) { @user }
      let(:root_folder) { Folder.root_folders(user).first }
      let(:request_url) { "/api/v1/folders/#{root_folder.id}/files?include[]=user" }
      let(:file) do
        Attachment.create!(
          filename: "ztest.txt",
          display_name: "ztest.txt",
          position: 1,
          uploaded_data: StringIO.new("file"),
          folder: root_folder,
          context: user,
          user:
        )
      end
      let(:request_params) do
        {
          controller: "files",
          action: "api_index",
          format: "json",
          id: root_folder.id.to_param,
          include: ["user"]
        }
      end

      before { file }

      it "includes user even for user files" do
        expect(subject.pluck("user")).to eql [
          {
            "id" => user.id,
            "anonymous_id" => user.id.to_s(36),
            "display_name" => user.short_name,
            "avatar_image_url" => User.avatar_fallback_url(nil, request),
            "html_url" => "http://www.example.com/about/#{user.id}",
            "pronouns" => nil
          }
        ]
      end

      context "when the request url contains the user id" do
        let(:request_url) { "/api/v1/users/#{user.id}/files" }
        let(:request_params) do
          {
            controller: "files",
            action: "api_index",
            format: "json",
            user_id: user.to_param
          }
        end

        it "triggers a user asset access live event" do
          expect(Canvas::LiveEvents).to receive(:asset_access).with(
            ["files", user],
            "files",
            "User",
            nil,
            { context: nil, context_membership: @user }
          )
          subject
        end
      end
    end
  end

  describe "#index for courses" do
    before :once do
      @root = Folder.root_folders(@course).first
      @f1 = @root.sub_folders.create!(name: "folder1", context: @course)
      @a1 = Attachment.create!(filename: "ztest.txt", display_name: "ztest.txt", position: 1, uploaded_data: StringIO.new("file"), folder: @f1, context: @course)
      @a3 = Attachment.create(filename: "atest3.txt", display_name: "atest3.txt", position: 2, uploaded_data: StringIO.new("file_"), folder: @f1, context: @course)
      @a3.hidden = true
      @a3.save!
      @a2 = Attachment.create!(filename: "mtest2.txt", display_name: "mtest2.txt", position: 3, uploaded_data: StringIO.new("file__"), folder: @f1, context: @course, locked: true)

      @files_path = "/api/v1/courses/#{@course.id}/files"
      @files_path_options = { controller: "files", action: "api_index", format: "json", course_id: @course.id.to_param }
    end

    context "with a 'category' query parameter" do
      subject do
        Attachment.find(
          api_call(:get, @files_path, @files_path_options, {}).pluck("id")
        )
      end

      let(:category) { Attachment::ICON_MAKER_ICONS }
      let(:icon_maker) { @a1 }
      let(:uncategorized) { @a2 }

      before do
        icon_maker.update!(category:)

        @files_path_options[:category] = category
      end

      it { is_expected.to include icon_maker }
      it { is_expected.not_to include uncategorized }
    end

    it "returns file category with the response" do
      json = api_call(:get, @files_path, @files_path_options, {})
      res = json.pluck("category")
      expect(res).to eq %w[uncategorized uncategorized uncategorized]
    end

    describe "sort" do
      it "lists files in alphabetical order" do
        json = api_call(:get, @files_path, @files_path_options, {})
        res = json.pluck("display_name")
        expect(res).to eq %w[atest3.txt mtest2.txt ztest.txt]
      end

      it "lists files in saved order if flag set" do
        json = api_call(:get, @files_path + "?sort_by=position", @files_path_options.merge(sort_by: "position"), {})
        res = json.pluck("display_name")
        expect(res).to eq %w[ztest.txt atest3.txt mtest2.txt]
      end

      it "sorts by size" do
        json = api_call(:get, @files_path + "?sort=size", @files_path_options.merge(sort: "size"))
        res = json.map { |f| [f["display_name"], f["size"]] }
        expect(res).to eq [["ztest.txt", 4], ["atest3.txt", 5], ["mtest2.txt", 6]]
      end

      it "sorts by last-modified time" do
        Timecop.freeze(2.hours.ago) { @a2.touch }
        Timecop.freeze(1.hour.ago) { @a1.touch }
        json = api_call(:get, @files_path + "?sort=updated_at", @files_path_options.merge(sort: "updated_at"))
        res = json.pluck("display_name")
        expect(res).to eq %w[mtest2.txt ztest.txt atest3.txt]
      end

      it "sorts by content_type" do
        @a1.update_attribute(:content_type, "application/octet-stream")
        @a2.update_attribute(:content_type, "video/quicktime")
        @a3.update_attribute(:content_type, "text/plain")
        json = api_call(:get, @files_path + "?sort=content_type", @files_path_options.merge(sort: "content_type"))
        res = json.map { |f| [f["display_name"], f["content-type"]] }
        expect(res).to eq [["ztest.txt", "application/octet-stream"], ["atest3.txt", "text/plain"], ["mtest2.txt", "video/quicktime"]]
      end

      it "sorts by user, nulls last" do
        @caller = @user
        @s1 = student_in_course(active_all: true, name: "alice").user
        @a1.update_attribute :user, @s1
        @s2 = student_in_course(active_all: true, name: "bob").user
        @a3.update_attribute :user, @s2
        @user = @caller
        json = api_call(:get, @files_path + "?sort=user", @files_path_options.merge(sort: "user"))
        res = json.map do |file|
          [file["display_name"], file["user"]["display_name"]]
        end
        expect(res).to eq [["ztest.txt", "alice"], ["atest3.txt", "bob"], ["mtest2.txt", nil]]
      end

      it "sorts in descending order" do
        json = api_call(:get, @files_path + "?sort=size&order=desc", @files_path_options.merge(sort: "size", order: "desc"))
        res = json.map { |f| [f["display_name"], f["size"]] }
        expect(res).to eq [["mtest2.txt", 6], ["atest3.txt", 5], ["ztest.txt", 4]]
      end
    end

    it "does not list locked file if not authed" do
      course_with_student_logged_in(course: @course)
      json = api_call(:get, @files_path, @files_path_options, {})
      expect(json.any? { |f| f[:id] == @a2.id }).to be false
    end

    it "does not list hidden files if not authed" do
      course_with_student_logged_in(course: @course)
      json = api_call(:get, @files_path, @files_path_options, {})

      expect(json.any? { |f| f[:id] == @a3.id }).to be false
    end

    it "does not list locked folder if not authed" do
      @f1.locked = true
      @f1.save!
      course_with_student_logged_in(course: @course)
      json = api_call(:get, @files_path, @files_path_options, {})

      expect(json).to eq []
    end

    it "paginates" do
      4.times { |i| Attachment.create!(filename: "test#{i}.txt", display_name: "test#{i}.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course) }
      json = api_call(:get, "/api/v1/courses/#{@course.id}/files?per_page=3", @files_path_options.merge(per_page: "3"), {})
      expect(json.length).to eq 3
      links = response.headers["Link"].split(",")
      expect(links.all? { |l| l =~ %r{api/v1/courses/#{@course.id}/files} }).to be_truthy
      expect(links.find { |l| l.include?('rel="next"') }).to match(/page=2/)
      expect(links.find { |l| l.include?('rel="first"') }).to match(/page=1/)
      expect(links.find { |l| l.include?('rel="last"') }).to match(/page=3/)

      json = api_call(:get, "/api/v1/courses/#{@course.id}/files?per_page=3&page=3", @files_path_options.merge(per_page: "3", page: "3"), {})
      expect(json.length).to eq 1
      links = response.headers["Link"].split(",")
      expect(links.all? { |l| l =~ %r{api/v1/courses/#{@course.id}/files} }).to be_truthy
      expect(links.find { |l| l.include?('rel="prev"') }).to match(/page=2/)
      expect(links.find { |l| l.include?('rel="first"') }).to match(/page=1/)
      expect(links.find { |l| l.include?('rel="last"') }).to match(/page=3/)
    end

    context "content_types" do
      before :once do
        attachment_model display_name: "thing.png", content_type: "image/png", context: @course, folder: @f1
        attachment_model display_name: "thing.gif", content_type: "image/gif", context: @course, folder: @f1
      end

      it "matches one content-type" do
        json = api_call(:get, @files_path + "?content_types=image", @files_path_options.merge(content_types: "image"), {})
        res = json.pluck("display_name")
        expect(res).to eq %w[thing.gif thing.png]
      end

      it "matches multiple content-types" do
        json = api_call(:get,
                        @files_path + "?content_types[]=text&content_types[]=image/gif",
                        @files_path_options.merge(content_types: ["text", "image/gif"]))
        res = json.pluck("display_name")
        expect(res).to eq %w[atest3.txt mtest2.txt thing.gif ztest.txt]
      end
    end

    it "searches for files by title" do
      atts = []
      2.times { |i| atts << Attachment.create!(filename: "first#{i}.txt", display_name: "first#{i}.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course) }
      2.times { |i| Attachment.create!(filename: "second#{i}.txt", display_name: "second#{i}.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course) }

      json = api_call(:get, @files_path + "?search_term=fir", @files_path_options.merge(search_term: "fir"), {})
      expect(json.pluck("id").sort).to eq atts.map(&:id).sort
    end

    describe "hidden folders" do
      before :once do
        hidden_subfolder = @f1.active_sub_folders.build(name: "hidden", context: @course)
        hidden_subfolder.workflow_state = "hidden"
        hidden_subfolder.save!
        hidden_subsub = hidden_subfolder.active_sub_folders.create!(name: "hsub", context: @course)
        @teh_file = Attachment.create!(filename: "implicitly hidden", uploaded_data: default_uploaded_data, folder: hidden_subsub, context: @course)
      end

      context "as teacher" do
        it "includes files in subfolders of hidden folders" do
          json = api_call(:get, @files_path, @files_path_options)
          expect(json.pluck("id")).to include @teh_file.id
        end
      end

      context "as student" do
        before :once do
          student_in_course active_all: true
        end

        it "excludes files in subfolders of hidden folders" do
          json = api_call(:get, @files_path, @files_path_options)
          expect(json.pluck("id")).not_to include @teh_file.id
        end
      end
    end
  end

  describe "#index other contexts" do
    it "operates on groups" do
      group_model
      attachment_model display_name: "foo", content_type: "text/plain", context: @group, folder: Folder.root_folders(@group).first
      account_admin_user
      json = api_call(:get, "/api/v1/groups/#{@group.id}/files", { controller: "files", action: "api_index", format: "json", group_id: @group.to_param })
      expect(json.pluck("id")).to eql [@attachment.id]
      expect(response.headers["Link"]).to include "/api/v1/groups/#{@group.id}/files"
    end

    it "operates on users" do
      user_model
      attachment_model display_name: "foo", content_type: "text/plain", context: @user, folder: Folder.root_folders(@user).first
      json = api_call(:get, "/api/v1/users/#{@user.id}/files", { controller: "files", action: "api_index", format: "json", user_id: @user.to_param })
      expect(json.pluck("id")).to eql [@attachment.id]
      expect(response.headers["Link"]).to include "/api/v1/users/#{@user.id}/files"
    end
  end

  describe "#show" do
    before do
      @root = Folder.root_folders(@course).first
      @att = Attachment.create!(filename: "test.png", display_name: "test-frd.png", uploaded_data: stub_png_data, folder: @root, context: @course)
      @file_path = "/api/v1/files/#{@att.id}"
      @file_path_options = { controller: "files", action: "api_show", format: "json", id: @att.id.to_param }
    end

    def attachment_json
      {
        "id" => @att.id,
        "folder_id" => @att.folder_id,
        "url" => file_download_url(@att, verifier: @att.uuid, download: "1", download_frd: "1"),
        "content-type" => "image/png",
        "display_name" => "test-frd.png",
        "filename" => @att.filename,
        "size" => @att.size,
        "unlock_at" => nil,
        "locked" => false,
        "hidden" => false,
        "lock_at" => nil,
        "locked_for_user" => false,
        "hidden_for_user" => false,
        "created_at" => @att.created_at.as_json,
        "updated_at" => @att.updated_at.as_json,
        "upload_status" => "success",
        "thumbnail_url" => thumbnail_image_url(@att, @att.uuid, host: "www.example.com"),
        "modified_at" => @att.modified_at.as_json,
        "mime_class" => @att.mime_class,
        "media_entry_id" => @att.media_entry_id,
        "canvadoc_session_url" => nil,
        "crocodoc_session_url" => nil,
        "category" => "uncategorized",
        "visibility_level" => @att.visibility_level
      }
    end

    double_testing_with_disable_adding_uuid_verifier_in_api_ff(attachment_variable_name: "att") do
      it "returns expected json" do
        json = api_call(:get, @file_path, @file_path_options, {})
        expected_json = attachment_json
        if disable_adding_uuid_verifier_in_api
          expected_json["url"] = file_download_url(@att, download: "1", download_frd: "1", verifier: nil)
        end
        expect(json).to eq(expected_json)
      end
    end

    it "does not omit verifiers when using session auth and params[:use_verifiers] is given" do
      user_session(@user)
      @att.root_account.disable_feature!(:disable_adding_uuid_verifier_in_api)
      get @file_path + "?use_verifiers=1"
      expect(response).to be_successful
      json = json_parse
      expect(json["url"]).to eq file_download_url(@att, download: "1", download_frd: "1", verifier: @att.uuid)
    end

    it "works with a context path" do
      user_session(@user)
      opts = @file_path_options.merge(course_id: @course.id.to_param)
      json = api_call(:get, "/api/v1/courses/#{@course.id}/files/#{@att.id}", opts, {})
      expect(json["id"]).to eq @att.id
    end

    it "404s with wrong context" do
      course_factory
      user_session(@user)
      opts = @file_path_options.merge(course_id: @course.id.to_param)
      api_call(:get, "/api/v1/courses/#{@course.id}/files/#{@att.id}", opts, {}, {}, expected_status: 404)
    end

    it "works with a valid verifier" do
      @att.context = @teacher
      @att.save!
      course_with_student(course: @course)
      user_session(@student)
      opts = @file_path_options.merge(user_id: @teacher.id.to_param, verifier: @att.uuid.to_param)
      api_call(:get, "/api/v1/users/#{@teacher.id}/files/#{@att.id}", opts, {}, {}, expected_status: 200)
    end

    it "403s with invalid verifier" do
      @att.context = @teacher
      @att.save!
      course_with_student(course: @course)
      user_session(@student)
      opts = @file_path_options.merge(user_id: @teacher.id.to_param, verifier: "nope")
      api_call(:get, "/api/v1/users/#{@teacher.id}/files/#{@att.id}", opts, {}, {}, expected_status: 403)
    end

    it "omits verifiers when using session auth" do
      user_session(@user)
      get @file_path
      expect(response).to be_successful
      json = json_parse
      expect(json["url"]).to eq file_download_url(@att, download: "1", download_frd: "1")
    end

    it "omits verifiers in the enhanced preview when using session auth" do
      user_session(@user)
      get @file_path + "?include[]=enhanced_preview_url"
      expect(response).to be_successful
      json = json_parse
      expect(json["preview_url"]).to eq context_url(@att.context, :context_file_file_preview_url, @att, annotate: 0)
    end

    it "passes along given verifiers when creating the enhanced_preview_url" do
      user_session(@user)
      @att.root_account.disable_feature!(:disable_adding_uuid_verifier_in_api)
      get @file_path + "?include[]=enhanced_preview_url&verifier=#{@att.uuid}"
      expect(response).to be_successful
      json = json_parse
      expect(json["preview_url"]).to eq context_url(@att.context, :context_file_file_preview_url, @att, annotate: 0, verifier: @att.uuid)
    end

    describe "with JWT access token" do
      include_context "InstAccess setup"

      before do
        @att.update!(instfs_uuid: "stuff", content_type: "application/pdf")
        user_with_pseudonym
        jwt_payload = {
          resource: "/courses/#{@course.id}/files/#{@att.id}?instfs_id=stuff",
          aud: [@course.root_account.uuid],
          sub: @user.uuid,
          tenant_auth: { location: "location" },
          iss: "instructure:inst_access",
          exp: 1.hour.from_now.to_i,
          iat: Time.now.to_i
        }
        @token_string = InstAccess::Token.send(:new, jwt_payload).to_unencrypted_token_string
        allow(Canvadocs).to receive(:enabled?).and_return(true)
        allow(InstFS).to receive_messages(enabled?: true, app_host: "http://instfs.test")
        stub_request(:get, "http://instfs.test/files/stuff/metadata").to_return(status: 200, body: { url: "http://instfs.test/stuff" }.to_json)
      end

      it "allows access" do
        json = api_call(:get, "/api/v1/files/#{@att.id}", { controller: "files", action: "api_show", format: "json", id: @att.id.to_param, include: "enhanced_preview_url", instfs_id: "stuff", access_token: @token_string }, {})
        expect(response).to be_successful

        expect(json["preview_url"]).to include "/courses/#{@course.id}/files/#{@att.id}/file_preview?access_token=#{@token_string}&annotate=0&instfs_id=stuff"
        expect(json["canvadoc_session_url"]).to include "access_token=#{@token_string}"
        query_params = Addressable::URI.parse(json["preview_url"]).query_values
        expect(query_params["access_token"]).to eq @token_string
        expect(query_params["instfs_id"]).to eq "stuff"
      end
    end

    it "returns lock information" do
      one_month_ago, one_month_from_now = 1.month.ago, 1.month.from_now
      att2 = Attachment.create!(filename: "test.txt", display_name: "test.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course, locked: true)
      att3 = Attachment.create!(filename: "test.txt", display_name: "test.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course, unlock_at: one_month_ago, lock_at: one_month_from_now)

      json = api_call(:get, "/api/v1/files/#{att2.id}", { controller: "files", action: "api_show", format: "json", id: att2.id.to_param }, {})
      expect(json["locked"]).to be_truthy
      expect(json["unlock_at"]).to be_nil
      expect(json["lock_at"]).to be_nil

      json = api_call(:get, "/api/v1/files/#{att3.id}", { controller: "files", action: "api_show", format: "json", id: att3.id.to_param }, {})
      expect(json["locked"]).to be_falsey
      expect(json["unlock_at"]).to eq one_month_ago.as_json
      expect(json["lock_at"]).to eq one_month_from_now.as_json
    end

    it "returns blueprint course restriction information when requested" do
      copy_from = course_factory(active_all: true)
      template = MasterCourses::MasterTemplate.set_as_master_course(copy_from)
      original_file = copy_from.attachments.create!(
        display_name: "cat_hugs.mp4", filename: "cat_hugs.mp4", content_type: "video/mp4", media_entry_id: "m-123456"
      )
      tag = template.create_content_tag_for!(original_file)
      tag.update(restrictions: { content: true })

      course_with_teacher(active_all: true)
      copy_to = @course
      template.add_child_course!(copy_to)

      # just create a copy directly instead of doing a real migration
      file_copy = copy_to.attachments.new(
        display_name: "cat_hugs.mp4", filename: "cat_hugs.mp4", content_type: "video/mp4", media_entry_id: "m-123456"
      )
      file_copy.migration_id = tag.migration_id
      file_copy.save!

      json = api_call(:get, "/api/v1/files/#{file_copy.id}", { controller: "files", action: "api_show", format: "json", id: file_copy.id.to_param }, { include: ["blueprint_course_status"] })
      expect(json["restricted_by_master_course"]).to be true
    end

    it "is not locked/hidden for a teacher" do
      att2 = Attachment.create!(filename: "test.txt", display_name: "test.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course, locked: true)
      att2.hidden = true
      att2.save!
      json = api_call(:get, "/api/v1/files/#{att2.id}", { controller: "files", action: "api_show", format: "json", id: att2.id.to_param }, { include: ["enhanced_preview_url"] })
      expect(json["locked"]).to be_truthy
      expect(json["hidden"]).to be_truthy
      expect(json["hidden_for_user"]).to be_falsey
      expect(json["locked_for_user"]).to be_falsey
      expect(json["preview_url"].include?("verifier")).to be_falsey
    end

    def should_be_locked(json)
      prohibited_fields = %w[
        canvadoc_session_url
        crocodoc_session_url
      ]

      expect(json["url"]).to eq ""
      expect(json["thumbnail_url"]).to eq ""
      expect(json["hidden"]).to be_truthy
      expect(json["hidden_for_user"]).to be_truthy
      expect(json["locked_for_user"]).to be_truthy
      expect(json["preview_url"].include?("verifier")).to be_falsey

      expect(json.keys & prohibited_fields).to be_empty
    end

    context "when the attachment is locked and replacement params are included" do
      subject do
        api_call(
          :get,
          "/api/v1/files/#{old_attachment.id}",
          { controller: "files", action: "api_show", format: "json", id: old_attachment.id.to_param }.merge(params)
        )
      end

      let(:old_attachment) do
        old = @course.attachments.build(display_name: "old file")
        old.file_state = "deleted"
        old.replacement_attachment = attachment
        old.save!
        old
      end

      let(:attachment) { @att }
      let(:params) do
        {
          id: old_attachment.id,
          replacement_chain_context_type: "course",
          replacement_chain_context_id: @course.id
        }
      end

      it "returns the replacement file" do
        expect(subject["id"]).to eq attachment.id
      end
    end

    context "as a student" do
      subject do
        api_call(:get, "/api/v1/files/#{@attachment.id}", { controller: "files", action: "api_show", format: "json", id: @attachment.id.to_param }, { include: ["enhanced_preview_url"] })
      end

      before do
        course_with_student_logged_in(course: @course)
        @attachment = Attachment.create!(attributes.merge(attr_overrides))
      end

      let(:attributes) { { filename: "test.txt", display_name: "test.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course } }
      let(:attr_overrides) { {} }

      context "when the attachment is hidden" do
        context "and the attachment is locked" do
          let(:attr_overrides) { { hidden: true, locked: true } }

          it "sets 'locked' to true" do
            expect(subject["locked"]).to be_truthy
          end

          it "shows the file is locked" do
            should_be_locked(subject)
          end
        end

        context "and the attachment has unlock_at and lock_at set" do
          let(:attr_overrides) { { hidden: true, unlock_at: 2.days.from_now, lock_at: 2.days.ago } }

          it "sets 'locked' to false" do
            expect(subject["locked"]).to be_falsey
          end

          it "shows the file is locked" do
            should_be_locked(subject)
          end
        end

        context "and the attachment is not locked in any way" do
          let(:attr_overrides) { { hidden: true } }

          double_testing_with_disable_adding_uuid_verifier_in_api_ff do
            it "includes the the file url" do
              expect(subject["url"]).to eq file_download_url(@attachment, verifier: disable_adding_uuid_verifier_in_api ? nil : @attachment.uuid, download: "1", download_frd: "1")
            end
          end

          it "does not show the file is locked" do
            expect(subject["locked"]).to be_falsey
            expect(subject["locked_for_user"]).to be_falsey
          end

          it "includes a preview URL" do
            expect(subject["preview_url"]).not_to be_nil
          end
        end
      end

      context "when the attachment is locked" do
        let(:attr_overrides) { { locked: true } }

        it "sets 'locked_to_user' to true" do
          expect(subject["locked_for_user"]).to be_truthy
        end

        it "sets a preview url" do
          expect(subject["preview_url"]).not_to be_nil
        end
      end

      context "when the file is scheduled to be locked" do
        let(:attr_overrides) { { unlock_at: 2.days.from_now, lock_at: 2.days.ago } }

        it "sets 'locked_to_user' to true" do
          expect(subject["locked_for_user"]).to be_truthy
        end

        it "sets a preview url" do
          expect(subject["preview_url"]).not_to be_nil
        end
      end

      context "enrolled in limited access account" do
        before do
          @course.account.root_account.enable_feature!(:allow_limited_access_for_students)
          @course.account.settings[:enable_limited_access_for_students] = true
          @course.account.save!
        end

        it "renders forbidden if called via API" do
          api_call(:get, @file_path, @file_path_options, {})
          expect(response).to have_http_status :forbidden
        end

        double_testing_with_disable_adding_uuid_verifier_in_api_ff do
          it "returns expected json if called from UI" do
            json = api_call(:get, @file_path, @file_path_options, {}, { "HTTP_REFERER" => "https://rspec.instructure.com" })
            expected_json = attachment_json
            if disable_adding_uuid_verifier_in_api
              expected_json["url"] = file_download_url(@att, download: "1", download_frd: "1", verifier: nil)
            end
            expect(json).to eq(expected_json)
          end
        end
      end
    end

    it "returns not found error" do
      expect { api_call(:get, "/api/v1/files/0", @file_path_options.merge(id: "0"), {}, {}, expected_status: 404) }.not_to change { ErrorReport.count }
    end

    it "returns not found for deleted attachment" do
      @att.destroy
      api_call(:get, @file_path, @file_path_options, {}, {}, expected_status: 404)
    end

    it "returns no permissions error for no context enrollment" do
      course_with_teacher(active_all: true, user: user_with_pseudonym)
      api_call(:get, @file_path, @file_path_options, {}, {}, expected_status: 403)
    end

    it "returns a hidden file" do
      course_with_student(course: @course)
      @att.hidden = true
      @att.save!
      api_call(:get, @file_path, @file_path_options, {}, {}, expected_status: 200)
    end

    it "returns user if requested" do
      @att.update_attribute(:user, @user)
      json = api_call(:get, @file_path + "?include[]=user", @file_path_options.merge(include: ["user"]))
      expect(json["user"]).to eql({
                                    "id" => @user.id,
                                    "anonymous_id" => @user.id.to_s(36),
                                    "display_name" => @user.short_name,
                                    "avatar_image_url" => User.avatar_fallback_url(nil, request),
                                    "html_url" => "http://www.example.com/courses/#{@course.id}/users/#{@user.id}",
                                    "pronouns" => nil
                                  })
    end

    it "returns usage_rights if requested" do
      @att.usage_rights = @course.usage_rights.create! legal_copyright: "(C) 2012 Initrode", use_justification: "creative_commons", license: "cc_by_sa"
      @att.save!
      json = api_call(:get, @file_path + "?include[]=usage_rights", @file_path_options.merge(include: ["usage_rights"]))
      expect(json["usage_rights"]).to eql({
                                            "legal_copyright" => "(C) 2012 Initrode",
                                            "use_justification" => "creative_commons",
                                            "license" => "cc_by_sa",
                                            "license_name" => "CC Attribution Share Alike"
                                          })
    end

    it "views file in Horizon course with query params set" do
      @course.account.enable_feature!(:horizon_course_setting)
      @course.update!(horizon_course: true)

      api_options = { controller: "files", action: "api_show", format: "json", course_id: @course.id, id: @att.id.to_param }
      json = api_call(:get, "/api/v1/courses/#{@course.id}/files/#{@att.id}" + "?view=true", api_options.merge(view: true))
      expect(json["view"]).to be_truthy
    end

    it "does not view file if not a Horizon course" do
      api_options = { controller: "files", action: "api_show", format: "json", course_id: @course.id, id: @att.id.to_param }
      json = api_call(:get, "/api/v1/courses/#{@course.id}/files/#{@att.id}" + "?view=true", api_options.merge(view: true))
      expect(json["view"]).to be_nil
    end
  end

  describe "#file_ref" do
    before :once do
      attachment_model(context: @course, filename: "hello.txt")
      @mig_id = "i567b573b77fab13a1a39937c24ae88f2"
      @attachment.update migration_id: @mig_id
    end

    it "finds a file by migration_id" do
      json = api_call(:get,
                      "/api/v1/courses/#{@course.to_param}/files/file_ref/#{@mig_id}",
                      controller: "files",
                      action: "file_ref",
                      format: "json",
                      course_id: @course.to_param,
                      migration_id: @mig_id)
      expect(json["id"]).to eq @attachment.id
      expect(json["display_name"]).to eq @attachment.display_name
    end

    it "requires permissions" do
      user_factory
      api_call(:get,
               "/api/v1/courses/#{@course.to_param}/files/file_ref/#{@mig_id}",
               { controller: "files",
                 action: "file_ref",
                 format: "json",
                 course_id: @course.to_param,
                 migration_id: @mig_id },
               {},
               {},
               { expected_status: 403 })
    end

    it "404s if given a bad migration id" do
      api_call(:get,
               "/api/v1/courses/#{@course.to_param}/files/file_ref/lolcats",
               { controller: "files",
                 action: "file_ref",
                 format: "json",
                 course_id: @course.to_param,
                 migration_id: "lolcats" },
               {},
               {},
               { expected_status: 404 })
    end
  end

  describe "#destroy" do
    before :once do
      @root = Folder.root_folders(@course).first
      @att = Attachment.create!(filename: "test.txt", display_name: "test.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course)
      @file_path = "/api/v1/files/#{@att.id}"
      @file_path_options = { controller: "files", action: "destroy", format: "json", id: @att.id.to_param }
    end

    it "deletes a file" do
      api_call(:delete, @file_path, @file_path_options)
      @att.reload
      expect(@att.file_state).to eq "deleted"
    end

    it "delete/replaces a file" do
      u = user_with_pseudonym(account: @account)
      account_admin_user(account: @account)
      @att.context = u
      @att.save!
      expect_any_instantiation_of(@att).to receive(:destroy_content_and_replace).once
      @file_path_options[:replace] = true
      api_call(:delete, @file_path, @file_path_options, {}, {}, expected_status: 200)
    end

    it "delete/replaces a file tied to an assignment" do
      assignment = @course.assignments.create!(title: "one")
      account_admin_user(account: @account)
      @att.context = assignment
      @att.save!
      expect_any_instantiation_of(@att).to receive(:destroy_content_and_replace).once
      @file_path_options[:replace] = true
      api_call(:delete, @file_path, @file_path_options, {}, {}, expected_status: 200)
    end

    it "delete/replaces a file tied to a quiz submission" do
      course_with_student(active_all: true)
      quiz_model(course: @course)
      @quiz.update_attribute :one_question_at_a_time, true
      @qs = @quiz.generate_submission(@student, false)

      account_admin_user(account: @account)
      @att.context = @qs
      @att.save!
      expect_any_instantiation_of(@att).to receive(:destroy_content_and_replace).once
      @file_path_options[:replace] = true
      api_call(:delete, @file_path, @file_path_options, {}, {}, expected_status: 200)
    end

    it "is not authorized to delete/replace a file" do
      course_with_teacher(active_all: true, user: user_with_pseudonym)
      @file_path_options[:replace] = true
      api_call(:delete, @file_path, @file_path_options, {}, {}, expected_status: 403)
    end

    it "returns 404" do
      api_call(:delete, "/api/v1/files/0", @file_path_options.merge(id: "0"), {}, {}, expected_status: 404)
    end

    it "returns unauthorized error if not authorized to delete" do
      course_with_student(course: @course)
      api_call(:delete, @file_path, @file_path_options, {}, {}, expected_status: 401)
    end

    context "as teacher without manage_files_delete permission" do
      before do
        teacher_role = Role.get_built_in_role("TeacherEnrollment", root_account_id: @course.root_account.id)
        RoleOverride.create!(
          permission: "manage_files_delete",
          enabled: false,
          role: teacher_role,
          account: @course.root_account
        )
      end

      it "disallows deleting a file" do
        course_with_teacher(active_all: true, user: user_with_pseudonym, course: @course)
        @file_path_options[:replace] = false
        api_call(:delete,
                 @file_path,
                 @file_path_options,
                 {},
                 {},
                 expected_status: 401)
      end
    end
  end

  describe "#icon_metadata" do
    context "instfs file" do
      before do
        @root = Folder.root_folders(@course).first
        @icon = Attachment.create!(filename: "icon.svg",
                                   display_name: "icon.svg",
                                   uploaded_data: File.open("spec/fixtures/icon.svg"),
                                   folder: @root,
                                   context: @course,
                                   category: Attachment::ICON_MAKER_ICONS,
                                   instfs_uuid: "yes")
        @file_path = "/api/v1/files/#{@icon.id}/icon_metadata"
        @file_path_options = { controller: "files", action: "icon_metadata", format: "json", id: @icon.id.to_param }
        allow(InstFS).to receive(:authenticated_url).and_return(@icon.authenticated_s3_url)
        allow(CanvasHttp).to receive(:validate_url).and_return([@icon.authenticated_s3_url, URI.parse(@icon.authenticated_s3_url)])
        stub_request(:get, @icon.authenticated_s3_url).to_return(body: File.open("spec/fixtures/icon.svg"))
      end

      it "returns metadata from the icon" do
        api_call(:get, @file_path, @file_path_options, {}, {}, expected_status: 200)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq "image/svg+xml-icon-maker-icons"
        expect(json["encodedImage"]).to be_starts_with "data:image/svg+xml;base64,PHN2ZyB3aWR0aD"
      end

      it "gives unauthorized errors if the user is not authorized to view the file" do
        @icon.update(locked: true)
        course_with_student_logged_in(course: @course)
        api_call(:get, @file_path, @file_path_options, {}, {}, expected_status: 403)
      end

      it "gives bad request errors if the file is not an icon" do
        @icon.update(category: Attachment::UNCATEGORIZED)
        api_call(:get, @file_path, @file_path_options, {}, {}, expected_status: 400)
      end

      it "return 'no content' if the file doesn't have any metadata" do
        stub_request(:get, @icon.public_url).to_return(body: "<html>something that doesn't have any metadata</html>")
        raw_api_call(:get, @file_path, @file_path_options)
        assert_status(204)
      end

      context "streaming" do
        before do
          # force chunking so streaming will actually act like a stream
          mocked_http = Class.new(Net::HTTP) do
            def request(*)
              super do |response|
                response.instance_eval do
                  def read_body(*, &)
                    @body.each_char(&)
                  end
                end
                yield response if block_given?
                response
              end
            end
          end

          stub_const("Net::HTTP", mocked_http)
        end

        it "only downloads data until the end of the metadata tag" do
          # I cut most of the original icon file off so that the XML is invalid if you read the whole thing,
          # but left enough that the metadata will be present and there will be a buffer for the http request
          # to read without erroring unless it downloads/parses too much of the file
          stub_request(:get, @icon.public_url).to_return(body: File.open("spec/fixtures/icon_with_bad_xml.svg"))
          api_call(:get, @file_path, @file_path_options, {}, {}, expected_status: 200)
          json = JSON.parse(response.body)
          expect(json["type"]).to eq "image/svg+xml-icon-maker-icons"
          expect(json["encodedImage"]).to be_starts_with "data:image/svg+xml;base64,PHN2ZyB3aWR0aD"
        end
      end
    end

    context "local file" do
      before do
        @root = Folder.root_folders(@course).first
        @icon = Attachment.create!(filename: "icon.svg",
                                   display_name: "icon.svg",
                                   uploaded_data: File.open("spec/fixtures/icon.svg"),
                                   folder: @root,
                                   context: @course,
                                   category: Attachment::ICON_MAKER_ICONS)
        @file_path = "/api/v1/files/#{@icon.id}/icon_metadata"
        @file_path_options = { controller: "files", action: "icon_metadata", format: "json", id: @icon.id.to_param }
        allow(CanvasHttp).to receive(:validate_url).and_return([@icon.authenticated_s3_url, URI.parse(@icon.authenticated_s3_url)])
        stub_request(:get, @icon.authenticated_s3_url).to_return(body: File.open("spec/fixtures/icon.svg"))
      end

      it "returns metadata from the icon" do
        api_call(:get, @file_path, @file_path_options, {}, {}, expected_status: 200)
        json = JSON.parse(response.body)
        expect(json["type"]).to eq "image/svg+xml-icon-maker-icons"
        expect(json["encodedImage"]).to be_starts_with "data:image/svg+xml;base64,PHN2ZyB3aWR0aD"
      end
    end
  end

  describe "#reset_verifier" do
    before :once do
      @root = Folder.root_folders(@course).first
      @att = Attachment.create!(filename: "test.txt", display_name: "test.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course)
      @file_path = "/api/v1/files/#{@att.id}/reset_verifier"
      @file_path_options = { controller: "files", action: "reset_verifier", format: "json", id: @att.id.to_param }
    end

    it "lets admin users reset verifiers" do
      old_uuid = @att.uuid
      account_admin_user(account: @account)
      api_call(:post, @file_path, @file_path_options, {}, {}, expected_status: 200)
      expect(@att.reload.uuid).to_not eq old_uuid
    end

    it "does not let non-admin users reset verifiers" do
      course_with_teacher(course: @course, active_all: true, user: user_with_pseudonym)
      api_call(:post, @file_path, @file_path_options, {}, {}, expected_status: 403)
    end

    context "as an admin without manage_files_edit or manage_files_delete permission" do
      before do
        @course.account.account_users.create(user: User.create!(name: "billy bob"))
        admin = admin_role(root_account_id: @course.account.resolved_root_account_id)
        @course.account.role_overrides.create(role: admin, enabled: false, permission: :manage_files_edit)
        @course.account.role_overrides.create(role: admin, enabled: false, permission: :manage_files_delete)
      end

      it "disallows letting admin users reset verifiers" do
        old_uuid = @att.uuid
        api_call(:post, @file_path, @file_path_options, {}, {}, expected_status: 403)
        expect(@att.reload.uuid).to eq old_uuid
      end
    end
  end

  describe "#rce_linked_file_instfs_ids" do
    before :once do
      course_with_teacher(active_all: true)
    end

    before do
      account_admin_user(account: @course.root_account)
      user_session(@user)
      allow(Canvadocs).to receive(:enabled?).and_return(true)
      allow(InstFS).to receive_messages(enabled?: true, app_host: "http://instfs.test")
    end

    it "allows access to course files the user has access to manage" do
      course = @course
      doc = attachment_model(context: course, display_name: "test.docx", uploaded_data: fixture_file_upload("test.docx"), instfs_uuid: "doc")
      image = attachment_model(context: course, display_name: "cn_image.jpg", uploaded_data: fixture_file_upload("cn_image.jpg"), instfs_uuid: "image")
      media = attachment_model(context: course, display_name: "292.mp3", uploaded_data: fixture_file_upload("292.mp3"), instfs_uuid: "media")
      diff_course = attachment_model(context: course_factory, display_name: "292.mp3", uploaded_data: fixture_file_upload("292.mp3"), instfs_uuid: "media2")

      file_urls = [
        "/courses/#{course.id}/files/#{doc.id}?wrap=1",
        "/courses/#{course.id}/files/#{image.id}/preview",
        "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true",
        "/media_attachments_iframe/#{diff_course.id}?type=video&amp;embedded=true"
      ]
      body = { user_uuid: @teacher.uuid, file_urls: }

      api_call(:post, "/api/v1/rce_linked_file_instfs_ids", { controller: "files", action: "rce_linked_file_instfs_ids", format: "json" }, body, {}, expected_status: 200)
      json = JSON.parse(response.body)
      expect(json).to eq({
                           "instfs_ids" => { "/courses/#{course.id}/files/#{image.id}/preview" => "image" },
                           "canvas_instfs_ids" => {
                             "/courses/#{course.id}/files/#{doc.id}?wrap=1" => "doc",
                             "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true" => "media"
                           }
                         })
    end

    it "allows access to user files the user has access to manage" do
      doc = attachment_model(context: @teacher, display_name: "test.docx", uploaded_data: fixture_file_upload("test.docx"), instfs_uuid: "doc")
      image = attachment_model(context: @teacher, display_name: "cn_image.jpg", uploaded_data: fixture_file_upload("cn_image.jpg"), instfs_uuid: "image")
      media = attachment_model(context: @teacher, display_name: "292.mp3", uploaded_data: fixture_file_upload("292.mp3"), instfs_uuid: "media")
      not_yours = attachment_model(context: @user, display_name: "292.mp3", uploaded_data: fixture_file_upload("292.mp3"), instfs_uuid: "media2")

      file_urls = [
        "/users/#{@teacher.id}/files/#{doc.id}?wrap=1",
        "/users/#{@teacher.id}/files/#{image.id}/preview",
        "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true",
        "/media_attachments_iframe/#{not_yours.id}?type=video&amp;embedded=true"
      ]
      body = { user_uuid: @teacher.uuid, file_urls: }

      api_call(:post, "/api/v1/rce_linked_file_instfs_ids", { controller: "files", action: "rce_linked_file_instfs_ids", format: "json" }, body, {}, expected_status: 200)
      json = JSON.parse(response.body)
      expect(json).to eq({
                           "instfs_ids" => { "/users/#{@teacher.id}/files/#{image.id}/preview" => "image" },
                           "canvas_instfs_ids" => {
                             "/users/#{@teacher.id}/files/#{doc.id}?wrap=1" => "doc",
                             "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true" => "media"
                           }
                         })
    end

    it "allows access to contextless files the user has access to manage" do
      doc = attachment_model(context: @course, display_name: "test.docx", uploaded_data: fixture_file_upload("test.docx"), instfs_uuid: "doc")

      file_urls = ["/files/#{doc.id}/download?download_frd=1", "/files/#{doc.id}", "http://example.canvas.edu/files/#{doc.id}/download"]
      body = { user_uuid: @teacher.uuid, file_urls: }

      api_call(:post, "/api/v1/rce_linked_file_instfs_ids", { controller: "files", action: "rce_linked_file_instfs_ids", format: "json" }, body, {}, expected_status: 200)
      json = JSON.parse(response.body)
      expect(json).to eq({
                           "canvas_instfs_ids" => {
                             "/files/#{doc.id}/download?download_frd=1" => "doc",
                             "/files/#{doc.id}" => "doc",
                             "http://example.canvas.edu/files/#{doc.id}/download" => "doc"
                           }
                         })
    end

    it "doesn't allow deleted file access" do
      doc = attachment_model(context: @course, display_name: "test.docx", uploaded_data: fixture_file_upload("test.docx"), instfs_uuid: "doc")
      image = attachment_model(context: @teacher, display_name: "cn_image.jpg", uploaded_data: fixture_file_upload("cn_image.jpg"), instfs_uuid: "image")
      media = attachment_model(context: @course, display_name: "292.mp3", uploaded_data: fixture_file_upload("292.mp3"), instfs_uuid: "media")
      Attachment.where(id: [doc, image, media]).destroy_all

      file_urls = [
        "/courses/#{@course.id}/files/#{doc.id}?wrap=1",
        "/courses/#{@course.id}/files/#{image.id}/preview",
        "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true",
      ]
      body = { user_uuid: @teacher.uuid, file_urls: }

      api_call(:post, "/api/v1/rce_linked_file_instfs_ids", { controller: "files", action: "rce_linked_file_instfs_ids", format: "json" }, body, {}, expected_status: 422)
      json = JSON.parse(response.body)
      expect(json).to eq({ "errors" => [{ "message" => "No valid file URLs given" }] })
    end

    it "shows hidden files" do
      doc = attachment_model(context: @course, display_name: "test.docx", uploaded_data: fixture_file_upload("test.docx"), instfs_uuid: "doc", file_state: "hidden")
      image = attachment_model(context: @course, display_name: "cn_image.jpg", uploaded_data: fixture_file_upload("cn_image.jpg"), instfs_uuid: "image", file_state: "hidden")
      media = attachment_model(context: @course, display_name: "292.mp3", uploaded_data: fixture_file_upload("292.mp3"), instfs_uuid: "media", file_state: "hidden")

      file_urls = [
        "/courses/#{@course.id}/files/#{doc.id}?wrap=1",
        "/courses/#{@course.id}/files/#{image.id}/preview",
        "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true",
      ]
      body = { user_uuid: @teacher.uuid, file_urls:, }

      api_call(:post, "/api/v1/rce_linked_file_instfs_ids", { controller: "files", action: "rce_linked_file_instfs_ids", format: "json" }, body, {}, expected_status: 200)
      json = JSON.parse(response.body)
      expect(json).to eq({
                           "instfs_ids" => { "/courses/#{@course.id}/files/#{image.id}/preview" => "image" },
                           "canvas_instfs_ids" => {
                             "/courses/#{@course.id}/files/#{doc.id}?wrap=1" => "doc",
                             "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true" => "media"
                           }
                         })
    end

    it "follows replaced files" do
      doc2 = attachment_model(context: @course, display_name: "test.docx", uploaded_data: fixture_file_upload("test.docx"), instfs_uuid: "doc2")
      image2 = attachment_model(context: @course, display_name: "cn_image.jpg", uploaded_data: fixture_file_upload("cn_image.jpg"), instfs_uuid: "image2")
      media2 = attachment_model(context: @course, display_name: "292.mp3", uploaded_data: fixture_file_upload("292.mp3"), instfs_uuid: "media2")

      doc = attachment_model(context: @course, display_name: "test.docx", uploaded_data: fixture_file_upload("test.docx"), instfs_uuid: "doc", replacement_attachment_id: doc2)
      image = attachment_model(context: @course, display_name: "cn_image.jpg", uploaded_data: fixture_file_upload("cn_image.jpg"), instfs_uuid: "image", replacement_attachment_id: image2)
      media = attachment_model(context: @course, display_name: "292.mp3", uploaded_data: fixture_file_upload("292.mp3"), instfs_uuid: "media", replacement_attachment_id: media2)
      Attachment.where(id: [doc, image, media]).destroy_all

      file_urls = [
        "/courses/#{@course.id}/files/#{doc.id}?wrap=1",
        "/courses/#{@course.id}/files/#{image.id}/preview",
        "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true",
      ]
      body = { user_uuid: @teacher.uuid, file_urls: }

      api_call(:post, "/api/v1/rce_linked_file_instfs_ids", { controller: "files", action: "rce_linked_file_instfs_ids", format: "json" }, body, {}, expected_status: 200)
      json = JSON.parse(response.body)
      expect(json).to eq({
                           "instfs_ids" => { "/courses/#{@course.id}/files/#{image.id}/preview" => "image2" },
                           "canvas_instfs_ids" => {
                             "/courses/#{@course.id}/files/#{doc.id}?wrap=1" => "doc2",
                             "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true" => "media2"
                           }
                         })
    end

    it "doesn't crash with bad urls" do
      media = attachment_model(context: @course, display_name: "292.mp3", uploaded_data: fixture_file_upload("292.mp3"), instfs_uuid: "media", replacement_attachment_id: media)

      file_urls = [
        "/courseles?wrap=1",
        "https://really-bad-url@",
        "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true",
      ]
      body = { user_uuid: @teacher.uuid, file_urls: }

      api_call(:post, "/api/v1/rce_linked_file_instfs_ids", { controller: "files", action: "rce_linked_file_instfs_ids", format: "json" }, body, {}, expected_status: 200)
      json = JSON.parse(response.body)
      expect(json).to eq({
                           "canvas_instfs_ids" => {
                             "/media_attachments_iframe/#{media.id}?type=video&amp;embedded=true" => "media"
                           }
                         })
    end

    it "limits the number of file links returned" do
      file_urls = []
      101.times { |i| file_urls << "/courses/#{@course.id}/files/#{i}?wrap=1" }
      body = { user_uuid: @teacher.uuid, file_urls:, location: "quiz/123" }
      api_call(:post, "/api/v1/rce_linked_file_instfs_ids", { controller: "files", action: "rce_linked_file_instfs_ids", format: "json" }, body, {}, expected_status: 422)

      json = JSON.parse(response.body)
      expect(json).to eq({ "errors" => [{ "message" => "Too many file links requested.  A maximum of 100 file links can be processed per request." }] })
    end

    it "returns the display name and instfs uuid when include_display_name is passed" do
      doc = attachment_model(context: @course, display_name: "test.docx", uploaded_data: fixture_file_upload("test.docx"), instfs_uuid: "doc")

      file_urls = ["/files/#{doc.id}/download?download_frd=1", "/files/#{doc.id}", "http://example.canvas.edu/files/#{doc.id}/download"]
      body = { user_uuid: @teacher.uuid, file_urls:, include_display_name: true }

      api_call(:post, "/api/v1/rce_linked_file_instfs_ids", { controller: "files", action: "rce_linked_file_instfs_ids", format: "json" }, body, {}, expected_status: 200)
      json = JSON.parse(response.body)
      expect(json).to eq({
                           "canvas_instfs_ids" => {
                             "/files/#{doc.id}/download?download_frd=1" =>
                                { "instfs_uuid" => "doc",
                                  "display_name" => "test.docx" },
                             "/files/#{doc.id}" =>
                                { "instfs_uuid" => "doc",
                                  "display_name" => "test.docx" },
                             "http://example.canvas.edu/files/#{doc.id}/download" =>
                                { "instfs_uuid" => "doc",
                                  "display_name" => "test.docx" }
                           }
                         })
    end
  end

  describe "#update" do
    before :once do
      @root = Folder.root_folders(@course).first
      @att = Attachment.create!(filename: "test.txt", display_name: "test.txt", uploaded_data: StringIO.new("file"), folder: @root, context: @course)
      @file_path = "/api/v1/files/#{@att.id}"
      @file_path_options = { controller: "files", action: "api_update", format: "json", id: @att.id.to_param }
    end

    double_testing_with_disable_adding_uuid_verifier_in_api_ff(attachment_variable_name: "att") do
      it "updates" do
        unlock = 1.day.from_now
        lock = 3.days.from_now
        new_params = { name: "newname.txt", locked: "true", hidden: true, unlock_at: unlock.iso8601, lock_at: lock.iso8601 }
        json = api_call(:put, @file_path, @file_path_options, new_params, {}, expected_status: 200)
        expect(json["url"]).to include "verifier=" unless disable_adding_uuid_verifier_in_api
        @att.reload
        expect(@att.display_name).to eq "newname.txt"
        expect(@att.locked).to be_truthy
        expect(@att.hidden).to be_truthy
        expect(@att.unlock_at.to_i).to eq unlock.to_i
        expect(@att.lock_at.to_i).to eq lock.to_i
      end
    end

    it "omits verifier in-app" do
      allow_any_instance_of(FilesController).to receive(:in_app?).and_return(true)
      allow_any_instance_of(FilesController).to receive(:verified_request?).and_return(true)

      new_params = { locked: "true" }
      json = api_call(:put, @file_path, @file_path_options, new_params)
      expect(json["url"]).not_to include "verifier="
    end

    it "moves to another folder" do
      @sub = @root.sub_folders.create!(name: "sub", context: @course)
      api_call(:put, @file_path, @file_path_options, { parent_folder_id: @sub.id.to_param }, {}, expected_status: 200)
      @att.reload
      expect(@att.folder_id).to eq @sub.id
    end

    describe "rename where file already exists" do
      before :once do
        @existing_file = Attachment.create! filename: "newname.txt", display_name: "newname.txt", uploaded_data: StringIO.new("blah"), folder: @root, context: @course
      end

      it "fails if on_duplicate isn't provided" do
        api_call(:put, @file_path, @file_path_options, { name: "newname.txt" }, {}, { expected_status: 409 })
        expect(@att.reload.display_name).to eq "test.txt"
        expect(@existing_file.reload).not_to be_deleted
      end

      it "overwrites if asked" do
        api_call(:put, @file_path, @file_path_options, { name: "newname.txt", on_duplicate: "overwrite" })
        expect(@att.reload.display_name).to eq "newname.txt"
        expect(@existing_file.reload).to be_deleted
        expect(@existing_file.replacement_attachment).to eq @att
      end

      it "renames if asked" do
        api_call(:put, @file_path, @file_path_options, { name: "newname.txt", on_duplicate: "rename" })
        expect(@existing_file.reload).not_to be_deleted
        expect(@existing_file.name).to eq "newname.txt"
        expect(@att.reload.display_name).not_to eq "test.txt"
        expect(@att.display_name).not_to eq "newname.txt"
        expect(@att.display_name).to start_with "newname"
        expect(@att.display_name).to end_with ".txt"
      end
    end

    describe "move where file already exists" do
      before :once do
        @sub = @root.sub_folders.create! name: "sub", context: @course
        @existing_file = Attachment.create! filename: "test.txt", display_name: "test.txt", uploaded_data: StringIO.new("existing"), folder: @sub, context: @course
      end

      it "fails if on_duplicate isn't provided" do
        api_call(:put, @file_path, @file_path_options, { parent_folder_id: @sub.to_param }, {}, { expected_status: 409 })
        expect(@existing_file.reload).not_to be_deleted
        expect(@att.reload.folder).to eq @root
      end

      it "overwrites if asked" do
        api_call(:put, @file_path, @file_path_options, { parent_folder_id: @sub.to_param, on_duplicate: "overwrite" })
        expect(@existing_file.reload).to be_deleted
        expect(@att.reload.folder).to eq @sub
        expect(@att.display_name).to eq @existing_file.display_name
      end

      it "renames if asked" do
        api_call(:put, @file_path, @file_path_options, { parent_folder_id: @sub.to_param, on_duplicate: "rename" })
        expect(@existing_file.reload).not_to be_deleted
        expect(@att.reload.folder).to eq @sub
        expect(@att.display_name).not_to eq @existing_file.display_name
      end
    end

    describe "submissions folder" do
      before(:once) do
        @student = user_model
        @root_folder = Folder.root_folders(@student).first
        @file = Attachment.create! filename: "file.txt", display_name: "file.txt", uploaded_data: StringIO.new("blah"), folder: @root_folder, context: @student
        @sub_folder = @student.submissions_folder
        @sub_file = Attachment.create! filename: "sub.txt", display_name: "sub.txt", uploaded_data: StringIO.new("bleh"), folder: @sub_folder, context: @student
      end

      it "does not move a file into a submissions folder" do
        api_call_as_user(@student,
                         :put,
                         "/api/v1/files/#{@file.id}",
                         { controller: "files", action: "api_update", format: "json", id: @file.to_param },
                         { parent_folder_id: @sub_folder.to_param },
                         {},
                         { expected_status: 403 })
      end

      it "does not move a file out of a submissions folder" do
        api_call_as_user(@student,
                         :put,
                         "/api/v1/files/#{@sub_file.id}",
                         { controller: "files", action: "api_update", format: "json", id: @sub_file.to_param },
                         { parent_folder_id: @root_folder.to_param },
                         {},
                         { expected_status: 403 })
      end
    end

    it "returns forbidden error" do
      course_with_student(course: @course)
      api_call(:put, @file_path, @file_path_options, { name: "new name" }, {}, expected_status: 403)
    end

    it "404s with invalid parent id" do
      api_call(:put, @file_path, @file_path_options, { parent_folder_id: 0 }, {}, expected_status: 404)
    end

    it "does not allow moving to different context" do
      user_root = Folder.root_folders(@user).first
      api_call(:put, @file_path, @file_path_options, { parent_folder_id: user_root.id.to_param }, {}, expected_status: 404)
    end

    it "truncates names over 255 characters" do
      overly_long_name = "hi" * 129

      truncated_overly_long_name = ("hi" * 126) + "..."

      api_call(:put, @file_path, @file_path_options, name: overly_long_name)
      updated_name = @att.reload.display_name

      aggregate_failures do
        expect(overly_long_name.length).to be > 255
        expect(updated_name.length).to be 255
        expect(updated_name).to eq truncated_overly_long_name
      end
    end

    context "with usage_rights_required" do
      before do
        @course.usage_rights_required = true
        @course.save!
        user_session(@teacher)
        @att.update_attribute(:locked, true)
      end

      it "does not publish if usage_rights unset" do
        api_call(:put, @file_path, @file_path_options, { locked: false }, {}, expected_status: 400)
        expect(@att.reload).to be_locked
      end

      it "publishes if usage_rights set" do
        @att.usage_rights = @course.usage_rights.create! use_justification: "public_domain"
        @att.save!
        api_call(:put, @file_path, @file_path_options, { locked: false }, {}, expected_status: 200)
        expect(@att.reload).not_to be_locked
      end
    end

    context "as teacher without manage_files_edit permission" do
      before do
        teacher_role = Role.get_built_in_role("TeacherEnrollment", root_account_id: @course.root_account.id)
        RoleOverride.create!(
          permission: "manage_files_edit",
          enabled: false,
          role: teacher_role,
          account: @course.root_account
        )
      end

      it "disallows an update" do
        unlock = 1.day.from_now
        lock = 3.days.from_now
        new_params = { name: "newname.txt", locked: "true", hidden: true, unlock_at: unlock.iso8601, lock_at: lock.iso8601 }
        api_call(:put, @file_path, @file_path_options, new_params, {}, expected_status: 403)
      end
    end
  end

  describe "quota" do
    let_once(:t_course) do
      course_with_teacher active_all: true
      @course.storage_quota = 111.megabytes
      @course.save
      attachment_model context: @course, size: 33.megabytes
      @course
    end

    let_once(:t_teacher) do
      t_course.teachers.first
    end

    before do
      user_session(@teacher)
    end

    it "returns total and used quota" do
      json = api_call_as_user(t_teacher,
                              :get,
                              "/api/v1/courses/#{t_course.id}/files/quota",
                              controller: "files",
                              action: "api_quota",
                              format: "json",
                              course_id: t_course.to_param)
      expect(json).to eql({ "quota" => 111.megabytes, "quota_used" => 33.megabytes })
    end

    it "requires manage_files permissions" do
      student_in_course course: t_course, active_all: true
      api_call_as_user(@student,
                       :get,
                       "/api/v1/courses/#{t_course.id}/files/quota",
                       { controller: "files", action: "api_quota", format: "json", course_id: t_course.to_param },
                       {},
                       {},
                       { expected_status: 403 })
    end

    it "operates on groups" do
      group = Account.default.groups.create!
      attachment_model context: group, size: 13.megabytes
      account_admin_user
      json = api_call(:get,
                      "/api/v1/groups/#{group.id}/files/quota",
                      controller: "files",
                      action: "api_quota",
                      format: "json",
                      group_id: group.to_param)
      expect(json).to eql({ "quota" => group.quota, "quota_used" => 13.megabytes })
    end

    it "operates on users if user == self" do
      course_with_student active_all: true
      json = api_call(:get,
                      "/api/v1/users/self/files/quota",
                      controller: "files",
                      action: "api_quota",
                      format: "json",
                      user_id: "self")
      expect(json).to eql({ "quota" => @student.quota, "quota_used" => 0 })
    end

    it "operates on users for account admins" do
      course_with_student active_all: true
      account_admin_user
      json = api_call_as_user(@admin,
                              :get,
                              "/api/v1/users/#{@student.id}/files/quota",
                              controller: "files",
                              action: "api_quota",
                              format: "json",
                              user_id: @student.id)
      expect(json).to eql({ "quota" => @student.quota, "quota_used" => 0 })
    end

    it "does not operate on users for non admin roles" do
      course_with_student active_all: true
      api_call_as_user(@teacher,
                       :get,
                       "/api/v1/users/#{@student.id}/files/quota",
                       controller: "files",
                       action: "api_quota",
                       format: "json",
                       user_id: @student.id)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
