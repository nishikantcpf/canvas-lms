# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
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

# @API Files
# @subtopic Folders
#
# @model Folder
#     {
#       "id": "Folder",
#       "description": "",
#       "properties": {
#         "context_type": {
#           "example": "Course",
#           "type": "string"
#         },
#         "context_id": {
#           "example": 1401,
#           "type": "integer"
#         },
#         "files_count": {
#           "example": 0,
#           "type": "integer"
#         },
#         "position": {
#           "example": 3,
#           "type": "integer"
#         },
#         "updated_at": {
#           "example": "2012-07-06T14:58:50Z",
#           "type": "datetime"
#         },
#         "folders_url": {
#           "example": "https://www.example.com/api/v1/folders/2937/folders",
#           "type": "string"
#         },
#         "files_url": {
#           "example": "https://www.example.com/api/v1/folders/2937/files",
#           "type": "string"
#         },
#         "full_name": {
#           "example": "course files/11folder",
#           "type": "string"
#         },
#         "lock_at": {
#           "example": "2012-07-06T14:58:50Z",
#           "type": "datetime"
#         },
#         "id": {
#           "example": 2937,
#           "type": "integer"
#         },
#         "folders_count": {
#           "example": 0,
#           "type": "integer"
#         },
#         "name": {
#           "example": "11folder",
#           "type": "string"
#         },
#         "parent_folder_id": {
#           "example": 2934,
#           "type": "integer"
#         },
#         "created_at": {
#           "example": "2012-07-06T14:58:50Z",
#           "type": "datetime"
#         },
#         "unlock_at": {
#           "type": "datetime"
#         },
#         "hidden": {
#           "example": false,
#           "type": "boolean"
#         },
#         "hidden_for_user": {
#           "example": false,
#           "type": "boolean"
#         },
#         "locked": {
#           "example": true,
#           "type": "boolean"
#         },
#         "locked_for_user": {
#           "example": false,
#           "type": "boolean"
#         },
#         "for_submissions": {
#           "example": false,
#           "type": "boolean",
#           "description": "If true, indicates this is a read-only folder containing files submitted to assignments"
#         }
#       }
#     }
#
class FoldersController < ApplicationController
  include Api::V1::Folders
  include Api::V1::Attachment
  include AttachmentHelper

  before_action :require_context, except: %i[list_folders_and_files api_index show api_destroy update create create_file copy_folder copy_file]
  before_action :check_limited_access_for_students, only: %i[create_file]

  def index
    if authorized_action(@context, @current_user, :read_files)
      render json: Folder.root_folders(@context).map { |f| f.as_json(permissions: { user: @current_user, session: }) }
    end
  end

  # @API List folders
  # @subtopic Folders
  # Returns the paginated list of folders in the folder.
  #
  # @example_request
  #
  #   curl 'https://<canvas>/api/v1/folders/<folder_id>/folders' \
  #        -H 'Authorization: Bearer <token>'
  #
  # @returns [Folder]
  def api_index
    @folder = Folder.find(params[:id])
    return unless authorized_action(@folder, @current_user, :read_contents)

    opts = lock_options(@folder.context, @current_user, session)

    scope = folder_index_scope(opts[:can_view_hidden_files])
    scope = if params[:sort_by] == "position"
              scope.by_position
            else
              scope.by_name
            end
    @folders = Api.paginate(scope, self, api_v1_list_folders_url(@folder))
    render json: folders_json(@folders, @current_user, session, opts)
  end

  # internal API
  def list_folders_and_files
    return render_json_unauthorized unless Account.site_admin.feature_enabled?(:files_a11y_rewrite)

    @folder = Folder.find(params[:id])
    if authorized_action(@folder, @current_user, :read_contents)
      items, opts, all_item_count = paginated_folders_and_files(api_v1_list_folders_and_files_url)
      headers["X-Total-Items"] = all_item_count.to_s
      render json: folders_or_files_json(items, @current_user, session, opts)
    else
      store_location(request.referer)
    end
  end

  # internal API
  def list_all_folders_and_files
    return render_json_unauthorized unless Account.site_admin.feature_enabled?(:files_a11y_rewrite)

    if authorized_action(@context, @current_user, :read_files)
      base_url = polymorphic_url([:api, :v1, @context, :folders_and_files])
      items, opts, all_item_count = paginated_folders_and_files(base_url)
      headers["X-Total-Items"] = all_item_count.to_s
      render json: folders_or_files_json(items, @current_user, session, opts)
    else
      store_location(request.referer)
    end
  end

  # Setup additional options based on context and permissions
  def lock_options(context, user, session)
    can_view_hidden_files = can_view_hidden_files?(context, user, session)
    opts = { can_view_hidden_files:, context: }
    if can_view_hidden_files &&
       context.is_a?(Course) &&
       MasterCourses::ChildSubscription.is_child_course?(context)
      opts[:master_course_restricted_folder_ids] = MasterCourses::FolderHelper.locked_folder_ids_for_course(context)
    end
    opts
  end

  def paginated_folders_and_files(base_url)
    opts = lock_options(@folder ? @folder.context : @context, @current_user, session)
    opts = opts.merge(include: params[:include]) if params[:include].present?

    folder_scope = folder_index_scope(opts[:can_view_hidden_files]).preload(:active_file_attachments, :active_sub_folders)
    file_scope = file_index_scope(@folder || @context, @current_user, params).preload(:attachment_upload_statuses, :root_attachment)

    collections = paginated_folders_and_files_collection(folder_scope, file_scope)

    per_page = Api.per_page_for(self, default: 25)

    combined = Api.paginate(
      BookmarkedCollection.concat(*collections),
      self,
      base_url,
      { per_page: }
    )

    if opts[:can_view_hidden_files] && opts[:context]
      opts[:master_course_status] = setup_master_course_restrictions(combined, opts[:context])
    end

    all_item_count = folder_scope.count + file_scope.count
    [combined, opts, all_item_count]
  end

  def paginated_folders_and_files_collection(folder_scope, file_scope)
    # Make copies of the scopes to avoid modifying the original ones
    folder_scope_copy = folder_scope
    file_scope_copy = file_scope

    folder_column_map = {
      "name" => Folder.best_unicode_collation_key("folders.name"),
      "updated_at" => "updated_at",
      "created_at" => "created_at"
    }

    file_column_map = {
      "name" => Attachment.best_unicode_collation_key("attachments.display_name"),
      "updated_at" => "updated_at",
      "created_at" => "created_at",
      "size" => "size",
      "modified_by" => { user: :sortable_name },
      "rights" => { usage_rights: :use_justification }
    }

    folder_sort = folder_column_map[params[:sort]] || "name"
    folder_desc = params[:order] == "desc" && folder_column_map.key?(params[:sort])
    file_sort = file_column_map[params[:sort]] || "display_name"
    file_desc = params[:order] == "desc"

    # Explicit LEFT JOIN for sorting by modified_by and rights
    if params[:sort] == "modified_by"
      file_scope_copy = file_scope_copy.left_outer_joins(:user).select("attachments.*, users.sortable_name AS sortable_name")
    elsif params[:sort] == "rights"
      file_scope_copy = file_scope_copy.left_outer_joins(:usage_rights).select("attachments.*, usage_rights.use_justification AS use_justification")
    end

    folder_bookmarker = Plannable::Bookmarker.new(Folder, folder_desc, folder_sort, :id)
    folders_collection = BookmarkedCollection.wrap(folder_bookmarker, folder_scope_copy)

    file_bookmarker = Plannable::Bookmarker.new(Attachment, file_desc, file_sort, :id)
    files_collection = BookmarkedCollection.wrap(file_bookmarker, file_scope_copy)

    [
      ["folders", folders_collection],
      ["files", files_collection]
    ]
  end

  def folder_index_scope(can_view_hidden_files)
    scope = @folder ? @folder.active_sub_folders : @context.active_folders
    scope = scope.not_hidden.not_locked unless can_view_hidden_files
    scope = Folder.search_by_attribute(scope, :name, params[:search_term], normalize_unicode: true) if params[:search_term].present?
    scope
  end

  # @API List all folders
  # @subtopic Folders
  # Returns the paginated list of all folders for the given context. This will
  # be returned as a flat list containing all subfolders as well.
  #
  # @example_request
  #
  #   curl 'https://<canvas>/api/v1/courses/<course_id>/folders' \
  #        -H 'Authorization: Bearer <token>'
  #
  # @returns [Folder]
  def list_all_folders
    if authorized_action(@context, @current_user, :read_files)
      can_view_hidden_files = can_view_hidden_files?(@context, @current_user, session)

      scope = folder_index_scope(can_view_hidden_files)
      scope = if params[:sort_by] == "position"
                scope.by_position
              else
                scope.by_name
              end

      url = named_context_url(@context, :api_v1_context_folders_url, include_host: true)
      folders = Api.paginate(scope, self, url)
      render json: folders_json(folders, @current_user, session, can_view_hidden_files:, context: @context)
    end
  end

  # @API Resolve path
  # @subtopic Folders
  # Given the full path to a folder, returns a list of all Folders in the path hierarchy,
  # starting at the root folder, and ending at the requested folder. The given path is
  # relative to the context's root folder and does not include the root folder's name
  # (e.g., "course files"). If an empty path is given, the context's root folder alone
  # is returned. Otherwise, if no folder exists with the given full path, a Not Found
  # error is returned.
  #
  # @example_request
  #
  #   curl 'https://<canvas>/api/v1/courses/<course_id>/folders/by_path/foo/bar/baz' \
  #        -H 'Authorization: Bearer <token>'
  #
  # @returns [Folder]
  def resolve_path
    # as long as one granted permission holds true, in most cases :read, user is authorized
    if authorized_action(@context, @current_user, [:read_files, *RoleOverride::GRANULAR_FILE_PERMISSIONS])
      can_view_hidden_files = can_view_hidden_files?(@context, @current_user, session)
      folders = Folder.resolve_path(@context, params[:full_path], can_view_hidden_files)
      raise ActiveRecord::RecordNotFound if folders.blank?

      render json: folders_json(folders, @current_user, session, can_view_hidden_files:, context: @context)
    else
      store_location(request.referer)
    end
  end

  # @API Get folder
  # @subtopic Folders
  # Returns the details for a folder
  #
  # You can get the root folder from a context by using 'root' as the :id.
  # For example, you could get the root folder for a course like:
  #
  # @example_request
  #   curl 'https://<canvas>/api/v1/courses/1337/folders/root' \
  #        -H 'Authorization: Bearer <token>'
  #
  # @example_request
  #   curl 'https://<canvas>/api/v1/folders/<folder_id>' \
  #        -H 'Authorization: Bearer <token>'
  #
  # @returns Folder
  def show
    if api_request?
      if params[:id] == "root"
        require_context
        @folder = Folder.root_folders(@context).first
      else
        get_context
        @folder = if @context
                    @context.folders.active.find(params[:id])
                  else
                    Folder.find(params[:id])
                  end
      end
    else
      require_context
      @folder = @context.folders.find(params[:id])
    end
    raise ActiveRecord::RecordNotFound if @folder.deleted?

    if authorized_action(@folder, @current_user, :read_contents)
      if api_request?
        render json: folder_json(@folder, @current_user, session)
      else
        respond_to do |format|
          format.html { redirect_to named_context_url(@context, :context_files_url, folder_id: @folder.id) }
          can_view_hidden_files = can_view_hidden_files?(@context, @current_user, session)

          files = if can_view_hidden_files
                    @folder.active_file_attachments.by_position_then_display_name
                  else
                    @folder.visible_file_attachments.not_hidden.not_locked.by_position_then_display_name
                  end
          files_options = { permissions: { user: @current_user }, methods: %i[currently_locked mime_class readable_size], only: %i[id comments content_type context_id context_type display_name folder_id position media_entry_id filename workflow_state] }
          folders_options = { permissions: { user: @current_user }, methods: [:currently_locked, :mime_class], only: %i[id context_id context_type lock_at name parent_folder_id position unlock_at] }
          sub_folders_scope = folder_index_scope(can_view_hidden_files)
          res = {
            actual_folder: @folder.as_json(folders_options),
            sub_folders: sub_folders_scope.by_position.map { |f| f.as_json(folders_options) },
            files: files.map do |f|
              f.as_json(files_options).tap do |json|
                json["attachment"].merge! doc_preview_json(f)
              end
            end
          }
          format.json { render json: res }
        end
      end
    end
  end

  # @API Update folder
  # @subtopic Folders
  # Updates a folder
  #
  # @argument name [String]
  #   The new name of the folder
  #
  # @argument parent_folder_id [String]
  #   The id of the folder to move this folder into. The new folder must be in the same context as the original parent folder.
  #
  # @argument lock_at [DateTime]
  #   The datetime to lock the folder at
  #
  # @argument unlock_at [DateTime]
  #   The datetime to unlock the folder at
  #
  # @argument locked [Boolean]
  #   Flag the folder as locked
  #
  # @argument hidden [Boolean]
  #   Flag the folder as hidden
  #
  # @argument position [Integer]
  #   Set an explicit sort position for the folder
  #
  # @example_request
  #
  #   curl -XPUT 'https://<canvas>/api/v1/folders/<folder_id>' \
  #        -F 'name=<new_name>' \
  #        -F 'locked=true' \
  #        -H 'Authorization: Bearer <token>'
  #
  # @returns Folder
  def update
    folder_params = process_folder_params(params, api_request?)
    if api_request?
      @folder = Folder.find(params[:id])
      @context = @folder.context
    else
      require_context
      @folder = @context.folders.find(params[:id])
    end
    if authorized_action(@folder, @current_user, :update)
      respond_to do |format|
        just_hide = folder_params.delete(:just_hide)
        if just_hide == "1"
          folder_params[:locked] = false
          folder_params[:hidden] = true
        end
        if (parent_folder_id = folder_params.delete(:parent_folder_id))
          parent_folder = @context.folders.active.find(parent_folder_id)
          return unless authorized_action(parent_folder, @current_user, :manage_contents)

          folder_params[:parent_folder] = parent_folder
        end
        if @folder.update(folder_params)
          if !@folder.parent_folder_id || !@context.folders.where(id: @folder).first
            @folder.parent_folder = Folder.root_folders(@context).first
            @folder.save
          end
          flash[:notice] = t :event_updated, "Event was successfully updated."
          format.html { redirect_to named_context_url(@context, :context_files_url) }
          if api_request?
            format.json { render json: folder_json(@folder, @current_user, session) }
          else
            format.json { render json: @folder.as_json(methods: [:currently_locked], permissions: { user: @current_user, session: }), status: :ok }
          end
        else
          format.html { render :edit }
          format.json { render json: @folder.errors, status: :bad_request }
        end
      end
    end
  end

  # @API Create folder
  # @subtopic Folders
  # Creates a folder in the specified context
  #
  # @argument name [Required, String]
  #   The name of the folder
  #
  # @argument parent_folder_id [String]
  #   The id of the folder to store the new folder in. An error will be returned if this does not correspond to an existing folder. If this and parent_folder_path are sent an error will be returned. If neither is given, a default folder will be used.
  #
  # @argument parent_folder_path [String]
  #   The path of the folder to store the new folder in. The path separator is the forward slash `/`, never a back slash. The parent folder will be created if it does not already exist. This parameter only applies to new folders in a context that has folders, such as a user, a course, or a group. If this and parent_folder_id are sent an error will be returned. If neither is given, a default folder will be used.
  #
  # @argument lock_at [DateTime]
  #   The datetime to lock the folder at
  #
  # @argument unlock_at [DateTime]
  #   The datetime to unlock the folder at
  #
  # @argument locked [Boolean]
  #   Flag the folder as locked
  #
  # @argument hidden [Boolean]
  #   Flag the folder as hidden
  #
  # @argument position [Integer]
  #   Set an explicit sort position for the folder
  #
  # @example_request
  #
  #   curl 'https://<canvas>/api/v1/folders/<folder_id>/folders' \
  #        -F 'name=<new_name>' \
  #        -F 'locked=true' \
  #        -H 'Authorization: Bearer <token>'
  #
  #
  # @example_request
  #
  #   curl 'https://<canvas>/api/v1/courses/<course_id>/folders' \
  #        -F 'name=<new_name>' \
  #        -F 'locked=true' \
  #        -H 'Authorization: Bearer <token>'
  #
  # @returns Folder
  def create
    folder_params = process_folder_params(params, api_request?)
    source_folder_id = folder_params.delete(:source_folder_id)
    if folder_params[:folder_id]
      parent_folder = Folder.find(folder_params[:folder_id])
      @context = parent_folder.context
    else
      require_context
    end

    if (folder_params[:folder_id] && (folder_params[:parent_folder_path] || folder_params[:parent_folder_id])) ||
       (folder_params[:parent_folder_path] && folder_params[:parent_folder_id])
      render json: { message: t("only_one_folder", "Can't set folder path and folder id") }, status: :bad_request
      return
    elsif folder_params[:folder_id]
      folder_params.delete(:folder_id)
    elsif folder_params[:parent_folder_id]
      parent_folder = @context.folders.active.find_by(id: folder_params.delete(:parent_folder_id))
      if parent_folder.nil?
        return render json: {
                        errors: [{ message: t("The specified resource does not exist.") }]
                      },
                      status: :not_found
      end
    elsif @context.respond_to?(:folders) && folder_params[:parent_folder_path].is_a?(String)
      root = Folder.root_folders(@context).first
      if authorized_action(root, @current_user, :create)
        parent_folder = Folder.assert_path(folder_params.delete(:parent_folder_path), @context)
      else
        return
      end
    end
    return if parent_folder && !authorized_action(parent_folder, @current_user, :manage_contents)

    folder_params[:parent_folder] = parent_folder

    @folder = @context.folders.build(folder_params)
    if authorized_action(@folder, @current_user, :create)
      if !@folder.parent_folder_id || !@context.folders.where(id: @folder.parent_folder_id).first
        @folder.parent_folder_id = Folder.unfiled_folder(@context).id
      end
      if source_folder_id.present? && (source_folder = Folder.where(id: source_folder_id).first) && source_folder.grants_right?(@current_user, session, :read)
        @folder = source_folder.clone_for(@context, @folder, { everything: true })
      end
      respond_to do |format|
        if @folder.save
          flash.now[:notice] = t :folder_created, "Folder was successfully created."
          format.html { redirect_to named_context_url(@context, :context_files_url) }
          if api_request?
            format.json { render json: folder_json(@folder, @current_user, session) }
          else
            format.json { render json: @folder.as_json(permissions: { user: @current_user, session: }) }
          end
        else
          format.html { render :new }
          format.json { render json: @folder.errors, status: :bad_request }
        end
      end
    end
  end

  def process_folder_params(parameters, api_request)
    folder_params = (api_request ? parameters : parameters[:folder]) || {}
    folder_params.permit(:name,
                         :parent_folder_id,
                         :parent_folder_path,
                         :folder_id,
                         :source_folder_id,
                         :lock_at,
                         :unlock_at,
                         :locked,
                         :hidden,
                         :context,
                         :position,
                         :just_hide)
  end
  private :process_folder_params

  def destroy
    @folder = Folder.find(params[:id])
    if authorized_action(@folder, @current_user, :delete)
      @folder.destroy
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :context_files_url) } # show.rhtml
        format.json { render json: @folder }
      end
    end
  end

  # @API Delete folder
  # @subtopic Folders
  # Remove the specified folder. You can only delete empty folders unless you
  # set the 'force' flag
  #
  # @argument force [Boolean]
  #   Set to 'true' to allow deleting a non-empty folder
  #
  # @example_request
  #
  #   curl -X DELETE 'https://<canvas>/api/v1/folders/<folder_id>' \
  #        -H 'Authorization: Bearer <token>'
  def api_destroy
    @folder = Folder.find(params[:id])
    if authorized_action(@folder, @current_user, :delete)
      if @folder.root_folder?
        render json: { message: t("no_deleting_root", "Can't delete the root folder") }, status: :bad_request
      elsif @folder.context.is_a?(Course) &&
            MasterCourses::ChildSubscription.is_child_course?(@folder.context) &&
            MasterCourses::FolderHelper.locked_folder_ids_for_course(@folder.context).include?(@folder.id)
        render json: { message: "Can't delete folder containing files locked by Blueprint Course" }, status: :bad_request
      elsif @folder.has_contents? && params[:force] != "true"
        render json: { message: t("no_deleting_folders_with_content", "Can't delete a folder with content") }, status: :bad_request
      else
        @context = @folder.context
        @folder.destroy
        render json: folder_json(@folder, @current_user, session)
      end
    end
  end

  # @API Upload a file
  #
  # Upload a file to a folder.
  #
  # This API endpoint is the first step in uploading a file.
  # See the {file:file.file_uploads.html File Upload Documentation} for details on
  # the file upload workflow.
  #
  # Only those with the "Manage Files" permission on a course or group can
  # upload files to a folder in that course or group.
  def create_file
    @folder = Folder.find(params[:folder_id])
    params[:parent_folder_id] = @folder.id
    @context = @folder.context
    @attachment = Attachment.new(context: @context)
    if authorized_action(@attachment, @current_user, :create)
      api_attachment_preflight(@context, request, params:, check_quota: true)
    end
  end

  # @API Copy a file
  #
  # Copy a file from elsewhere in Canvas into a folder.
  #
  # Copying a file across contexts (between courses and users) is permitted,
  # but the source and destination must belong to the same institution.
  #
  # @argument source_file_id [Required, String]
  #   The id of the source file
  #
  # @argument on_duplicate [Optional, String, "overwrite"|"rename"]
  #   What to do if a file with the same name already exists at the destination.
  #   If such a file exists and this parameter is not given, the call will fail.
  #
  #   "overwrite":: Replace an existing file with the same name
  #   "rename":: Add a qualifier to make the new filename unique
  #
  # @example_request
  #
  #   curl 'https://<canvas>/api/v1/folders/123/copy_file' \
  #        -H 'Authorization: Bearer <token>'
  #        -F 'source_file_id=456'
  #
  # @returns File
  def copy_file
    unless params[:source_file_id].present?
      return render json: { message: "source_file_id must be provided" }, status: :bad_request
    end

    @dest_folder = Folder.find(params[:dest_folder_id])
    return unless authorized_action(@dest_folder, @current_user, :manage_contents)

    @context = @dest_folder.context
    @source_file = Attachment.find(params[:source_file_id])
    unless @source_file.shard == @dest_folder.shard
      return render json: { message: "cannot copy across institutions" }, status: :bad_request
    end

    if authorized_action(@source_file, @current_user, :download)
      @attachment = @context.attachments.build(folder: @dest_folder)
      if authorized_action(@attachment, @current_user, :create)
        on_duplicate, name = params[:on_duplicate].presence, params[:name].presence
        duplicate_options = (on_duplicate == "rename" && name) ? { name: } : {}
        return render json: { message: "on_duplicate must be 'overwrite' or 'rename'" }, status: :bad_request if on_duplicate && %w[overwrite rename].exclude?(on_duplicate)
        if on_duplicate.nil? && @dest_folder.active_file_attachments.where(display_name: @source_file.display_name).exists?
          return render json: { message: "file already exists; set on_duplicate to 'rename' or 'overwrite'" }, status: :conflict
        end

        @attachment = @source_file.clone_for(@context, @attachment, force_copy: true)
        if @attachment.save
          # default to rename on race condition (if a file happened to be created after the check above, and on_duplicate was not given)
          @attachment.handle_duplicates((on_duplicate == "overwrite") ? :overwrite : :rename, duplicate_options)
          render json: attachment_json(@attachment, @current_user, {}, { omit_verifier_in_app: true })
        else
          render json: @attachment.errors
        end
      end
    end
  end

  # @API Copy a folder
  #
  # Copy a folder (and its contents) from elsewhere in Canvas into a folder.
  #
  # Copying a folder across contexts (between courses and users) is permitted,
  # but the source and destination must belong to the same institution.
  # If the source and destination folders are in the same context, the
  # source folder may not contain the destination folder. A folder will be
  # renamed at its destination if another folder with the same name already
  # exists.
  #
  # @argument source_folder_id [Required, String]
  #   The id of the source folder
  #
  # @example_request
  #
  #   curl 'https://<canvas>/api/v1/folders/123/copy_folder' \
  #        -H 'Authorization: Bearer <token>'
  #        -F 'source_file_id=789'
  #
  # @returns Folder
  def copy_folder
    if params[:source_folder_id].blank?
      return render json: { message: "source_folder_id must be provided" }, status: :bad_request
    end

    @dest_folder = Folder.find(params[:dest_folder_id])
    return unless authorized_action(@dest_folder, @current_user, :manage_contents)

    @context = @dest_folder.context
    @source_folder = Folder.find(params[:source_folder_id])
    unless @source_folder.shard == @dest_folder.shard
      return render json: { message: "cannot copy across institutions" }, status: :bad_request
    end
    if @source_folder.context == @context && (@dest_folder.full_name + "/").start_with?(@source_folder.full_name + "/")
      return render json: { message: "source folder may not contain destination folder" }, status: :bad_request
    end

    if authorized_action(@source_folder.context, @current_user, [*RoleOverride::GRANULAR_FILE_PERMISSIONS])
      @folder = @context.folders.build(parent_folder: @dest_folder)
      if authorized_action(@folder, @current_user, :create)
        @folder = @source_folder.clone_for(@context, @folder, everything: true, force_copy: true)
        if @folder.save
          render json: folder_json(@folder, @current_user, session)
        else
          render json: @folder.errors
        end
      end
    end
  end

  def icon_maker_folder
    require_context
    if @context.grants_any_right?(@current_user, session, *RoleOverride::GRANULAR_FILE_PERMISSIONS)
      @folder = Folder.icon_maker_folder(@context)
      render json: folder_json(@folder, @current_user, session)
    end
  end

  # @API Get uploaded media folder for user
  # @subtopic Folders
  # Returns the details for a designated upload folder that the user has rights to
  # upload to, and creates it if it doesn't exist.
  #
  # If the current user does not have the permissions to manage files
  # in the course or group, the folder will belong to the current user directly.
  #
  # @example_request
  #   curl 'https://<canvas>/api/v1/courses/1337/folders/media' \
  #        -H 'Authorization: Bearer <token>'
  #
  # @returns Folder
  def media_folder
    require_context
    if authorized_action(@context, @current_user, :read_files)
      folder_context =
        if @context.grants_any_right?(@current_user, session, *RoleOverride::GRANULAR_FILE_PERMISSIONS)
          @context
        else
          @current_user
        end
      @folder = Folder.media_folder(folder_context)
      render json: folder_json(@folder, @current_user, session)
    end
  end
end
