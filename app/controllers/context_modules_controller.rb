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

class ContextModulesController < ApplicationController
  include Api::V1::ContextModule
  include WebZipExportHelper
  include ContextExternalToolsHelper

  before_action :require_context

  include HorizonMode
  before_action :load_canvas_career, only: [:index, :show]

  add_crumb(proc { t("#crumbs.modules", "Modules") }) { |c| c.send :named_context_url, c.instance_variable_get(:@context), :context_context_modules_url }
  before_action { |c| c.active_tab = "modules" }

  include K5Mode

  LINK_ITEM_TYPES = %w[ExternalUrl ContextExternalTool].freeze

  module ModuleIndexHelper
    include ContextModulesHelper

    def load_module_file_details
      attachment_tags = GuardRail.activate(:secondary) { @context.module_items_visible_to(@current_user).where(content_type: "Attachment").preload(content: :folder).to_a }
      attachment_tags.each_with_object({}) do |file_tag, items|
        items[file_tag.id] = {
          id: file_tag.id,
          content_id: file_tag.content_id,
          content_details: content_details(file_tag, @current_user, for_admin: true),
          module_id: file_tag.context_module_id
        }
      end
    end

    def modules_cache_key
      @modules_cache_key ||= begin
        visible_assignments = @current_user.try(:learning_object_visibilities, @context)
        cache_key_items = [@context.cache_key,
                           @can_view,
                           @can_add,
                           @can_edit,
                           @can_delete,
                           @is_student,
                           @can_view_unpublished,
                           @context.is_a?(Course) ? @context.restrict_quantitative_data?(@current_user) : false,
                           "all_context_modules_draft_10",
                           collection_cache_key(@modules),
                           Time.zone,
                           Digest::SHA256.hexdigest([visible_assignments, @section_visibility, @module_ids_with_overrides].join("/"))]
        cache_key = cache_key_items.join("/")
        cache_key = add_menu_tools_to_cache_key(cache_key)
        add_mastery_paths_to_cache_key(cache_key, @context, @current_user)
      end
    end

    def load_modules
      @modules = @context.modules_visible_to(@current_user).limit(1000)
      @modules.each(&:check_for_stale_cache_after_unlocking!)
      module_collapsed_base = ContextModuleProgression.for_user(@current_user)
                                                      .for_modules(@modules)
                                                      .pluck(:context_module_id, :collapsed)
      @collapsed_modules = module_collapsed_base.select { |_cm_id, collapsed| collapsed == true }.map(&:first)
      @expanded_modules = module_collapsed_base.select { |_cm_id, collapsed| collapsed == false }.map(&:first)
      @section_visibility = @context.course_section_visibility(@current_user)
      @combined_active_quizzes = combined_active_quizzes

      load_permissions
      @viewable_module_ids = @modules.pluck(:id)

      @module_ids_with_overrides = AssignmentOverride.where(context_module_id: @modules).active.distinct.pluck(:context_module_id)

      modules_cache_key

      @is_cyoe_on = @current_user && ConditionalRelease::Service.enabled_in_context?(@context)
      if allow_web_export_download?
        @allow_web_export_download = true
        @last_web_export = @context.web_zip_exports.visible_to(@current_user).order("epub_exports.created_at").last
      end

      load_menu_tools

      if @context.grants_any_right?(@current_user, session, *RoleOverride::GRANULAR_MANAGE_COURSE_CONTENT_PERMISSIONS)
        module_file_details = load_module_file_details
      end

      @allow_menu_tools = @context.grants_right?(@current_user, session, :manage_course_content_add) &&
                          (@menu_tools[:module_index_menu].present? || @menu_tools[:module_index_menu_modal].present?)

      assign_to_tags = @context.account.feature_enabled?(:assign_to_differentiation_tags) && @context.account.allow_assign_to_differentiation_tags?

      hash = {
        course_id: @context.id,
        CONTEXT_URL_ROOT: polymorphic_path([@context]),
        FILES_CONTEXTS: [{ asset_string: @context.asset_string }],
        MODULE_FILE_DETAILS: module_file_details,
        MODULE_FILE_PERMISSIONS: {
          usage_rights_required: @context.usage_rights_required?,
          manage_files_edit: @context.grants_right?(@current_user, session, :manage_files_edit)
        },
        ALLOW_ASSIGN_TO_DIFFERENTIATION_TAGS: assign_to_tags,
        CAN_MANAGE_DIFFERENTIATION_TAGS: @context.grants_any_right?(@current_user, *RoleOverride::GRANULAR_MANAGE_TAGS_PERMISSIONS) && assign_to_tags,
        MODULE_TOOLS: module_tool_definitions,
        DEFAULT_POST_TO_SIS: @context.account.sis_default_grade_export[:value] && !AssignmentUtil.due_date_required_for_account?(@context.account),
        PUBLISH_FINAL_GRADE: Canvas::Plugin.find!("grade_export").enabled?,
        restrict_quantitative_data: @context.is_a?(Course) ? @context.restrict_quantitative_data?(@current_user) : false
      }

      is_master_course = MasterCourses::MasterTemplate.is_master_course?(@context)
      @is_child_course = MasterCourses::ChildSubscription.is_child_course?(@context)
      if is_master_course || @is_child_course
        hash[:MASTER_COURSE_SETTINGS] = {
          IS_MASTER_COURSE: is_master_course,
          IS_CHILD_COURSE: @is_child_course,
          MASTER_COURSE_DATA_URL: context_url(@context, :context_context_modules_master_course_info_url)
        }
      end
      if !@is_student && @is_child_course &&
         @context.account.feature_enabled?(:modules_page_hide_blueprint_lock_icon_for_children)
        hash[:HIDE_BLUEPRINT_LOCK_ICON_FOR_CHILDREN] = true
      end

      load_module_show_setting

      @feature_student_module_selection = @context.account.feature_enabled?(:modules_student_module_selection)
      @feature_teacher_module_selection = @context.account.feature_enabled?(:modules_teacher_module_selection)

      if @can_edit && (@feature_student_module_selection || @feature_teacher_module_selection)
        hash[:MODULE_FEATURES] = {}
        hash[:MODULE_FEATURES][:STUDENT_MODULE_SELECTION] = true if @feature_student_module_selection
        hash[:MODULE_FEATURES][:TEACHER_MODULE_SELECTION] = true if @feature_teacher_module_selection
      end

      append_default_due_time_js_env(@context, hash)
      js_env(hash)
      set_js_module_data
      conditional_release_js_env(includes: :active_rules)
    end

    def load_permissions
      @can_view = @context.grants_any_right?(@current_user, session, *RoleOverride::GRANULAR_MANAGE_COURSE_CONTENT_PERMISSIONS)
      @can_add = @context.grants_right?(@current_user, session, :manage_course_content_add)
      @can_edit = @context.grants_right?(@current_user, session, :manage_course_content_edit)
      @can_delete = @context.grants_right?(@current_user, session, :manage_course_content_delete)
      @can_view_grades = can_do(@context, @current_user, :view_all_grades)
      @is_student = @context.grants_right?(@current_user, session, :participate_as_student)
      @can_view_unpublished = @context.grants_right?(@current_user, session, :read_as_admin)
    end

    def load_menu_tools
      placements = %i[
        assignment_menu
        discussion_topic_menu
        file_menu
        module_menu
        quiz_menu
        wiki_page_menu
        module_index_menu
        module_group_menu
        module_index_menu_modal
        module_menu_modal
      ]
      tools = GuardRail.activate(:secondary) do
        Lti::ContextToolFinder.new(
          @context,
          placements:,
          current_user: @current_user
        ).all_tools_sorted_array
      end

      @menu_tools = {}
      placements.each do |p|
        @menu_tools[p] = tools.select { |t| t.has_placement? p }
      end
      @menu_tools
    end

    def load_module_show_setting
      @can_edit = @context.grants_right?(@current_user, session, :manage_course_content_edit)
      @feature_student_module_selection = @context.account.feature_enabled?(:modules_student_module_selection)
      @feature_teacher_module_selection = @context.account.feature_enabled?(:modules_teacher_module_selection)

      if @feature_student_module_selection || @feature_teacher_module_selection
        is_teacher = @context.user_has_been_teacher?(@current_user)
        has_admin_permissions = @context.grants_right?(@current_user, :read_as_admin)
        @module_show_setting = if @feature_teacher_module_selection && is_teacher
                                 @context.show_teacher_only_module_id
                               elsif @feature_student_module_selection && !has_admin_permissions
                                 @context.show_student_only_module_id
                               else
                                 0
                               end&.to_i
        @module_show_setting = nil if @module_show_setting&.zero?
      end
    end

    private

    def module_tool_definitions
      tools = {}
      # commons favorites tray placements expect tool in display_hash format
      %i[module_index_menu module_group_menu module_menu].each do |type|
        tools[type] = @menu_tools[type].map { |t| external_tool_display_hash(t, type) }
      end
      # newer modal placements expect tool in launch_definition format
      %i[module_index_menu_modal module_menu_modal].each do |type|
        tools[type] = Lti::AppLaunchCollator.launch_definitions(@menu_tools[type], [type])
      end
      tools
    end

    def combined_active_quizzes
      classic_quizzes = @context
                        .active_quizzes
                        .reorder(Quizzes::Quiz.best_unicode_collation_key("title"))
                        .limit(400)
                        .pluck(:id, :title, Arel.sql("'quiz' AS type"))

      lti_quizzes = @context
                    .active_assignments
                    .type_quiz_lti
                    .reorder(Assignment.best_unicode_collation_key("title"))
                    .limit(400)
                    .pluck(:id, :title, Arel.sql("'assignment' AS type"))

      @combined_active_quizzes_includes_both_types = !classic_quizzes.empty? && !lti_quizzes.empty?
      (classic_quizzes + lti_quizzes).sort_by { |quiz_attrs| Canvas::ICU.collation_key(quiz_attrs[1] || CanvasSort::First) }.take(400)
    end
  end
  include ModuleIndexHelper

  def index
    if authorized_action(@context, @current_user, :read)
      log_asset_access(["modules", @context], "modules", "other")

      load_modules

      set_tutorial_js_env

      @progress = Progress.find_by(
        context: @context,
        tag: "context_module_batch_update",
        workflow_state: ["queued", "running"]
      )

      if @is_student
        return unless tab_enabled?(@context.class::TAB_MODULES)

        @modules.each { |m| m.evaluate_for(@current_user) }
        session[:module_progressions_initialized] = true
      end
      add_body_class("padless-content")

      js_env(CONTEXT_MODULE_ASSIGNMENT_INFO_URL: context_url(@context, :context_context_modules_assignment_info_url))
      js_env(CONTEXT_MODULE_ESTIMATED_DURATION_INFO_URL: context_url(@context, :context_context_modules_estimated_duration_info_url))

      if @context.use_modules_rewrite_view?(@current_user, session)
        # Load new modules page assets
        context_modules_header_props = {
          title: t("Modules"),
          viewProgress: {
            label: t("links.student_progress", "View Progress"),
            url: progressions_course_context_modules_path(@context),
            visible: @can_view_grades,
          },
          publishMenu: {
            courseId: @context.id,
            runningProgressId: @progress&.id,
            disabled: @modules.empty?,
            visible: @context.grants_right?(@current_user, session, :manage_course_content_edit),
          },
          addModule: {
            label: t("Add Module"),
            visible: @can_add,
          },
          moreMenu: {
            label: t("Modules Settings"),
            menuTools: {
              items: external_tools_menu_items_raw_with_modules(@menu_tools, %i[module_index_menu module_index_menu_modal]),
              visible: @allow_menu_tools,
            },
            exportCourseContent: {
              label: t("Export Course Content"),
              url: context_url(@context, :context_start_offline_web_export_url),
              visible: @allow_web_export_download,
            },
          },
          lastExport: {
            label: t("#context_modules.last_export", "Last Export: "),
            url: context_url(@context, :context_offline_web_exports_url),
            date: @last_web_export.nil? ? nil : datetime_string(force_zone(@last_web_export.created_at)),
            visible: !@last_web_export.nil?
          },
        }
        js_env(CONTEXT_MODULES_HEADER_PROPS: context_modules_header_props)

        modules_permissions = {
          canAdd: @can_add,
          canEdit: @can_edit,
          canDelete: @can_delete,
          canViewUnpublished: @can_view_unpublished,
          canDirectShare: can_do(@context, @current_user, :direct_share),
          readAsAdmin: @context.grants_right?(@current_user, session, :read_as_admin)
        }

        observer_enrollments = @context.observer_enrollments.for_user(@current_user).active_or_pending
        is_observer = observer_enrollments.exists?
        observed_students = if is_observer && @context.grants_right?(@current_user, session, :read_roster)
                              observer_enrollments.includes(:associated_user).filter_map do |enrollment|
                                associated_user = enrollment.associated_user
                                if associated_user && enrollment.associated_user_id &&
                                   @context.enrollments.where(user_id: associated_user.id, workflow_state: ["active", "completed"]).exists?
                                  { id: associated_user.id.to_s, name: associated_user.name }
                                end
                              end
                            else
                              []
                            end

        modules_observer_info = {
          isObserver: is_observer,
          observedStudents: observed_students
        }

        js_env(MODULES_PERMISSIONS: modules_permissions)
        js_env(MODULES_OBSERVER_INFO: modules_observer_info)

        js_bundle :context_modules_v2
        css_bundle :content_next, :context_modules2, :context_modules_v2

        render html: "", layout: true
      else
        # Load legacy modules page assets
        js_bundle :context_modules
        css_bundle :content_next, :context_modules2
        render stream: can_stream_template?
      end
    end
  end

  def choose_mastery_path
    if authorized_action(@context, @current_user, :participate_as_student)
      id = params[:id]
      item = @context.context_module_tags.not_deleted.find(params[:id])

      if item.present? && item.published? && item.context_module.published?
        rules = ConditionalRelease::Service.rules_for(@context, @current_user, session)
        rule = conditional_release_rule_for_module_item(item, conditional_release_rules: rules)

        # locked assignments always have 0 sets, so this check makes it not return 404 if locked
        # but instead progress forward and return a warning message if is locked later on
        if rule.present? && (rule[:locked] || !rule[:selected_set_id] || rule[:assignment_sets].length > 1)
          if rule[:locked]
            flash[:warning] = t("Module Item is locked.")
            return redirect_to named_context_url(@context, :context_context_modules_url)
          else
            options = rule[:assignment_sets].map do |set|
              option = {
                setId: set[:id]
              }

              option[:assignments] = (set[:assignments] || set[:assignment_set_associations]).map do |a|
                assg = assignment_json(a[:model], @current_user, session)
                assg[:assignmentId] = a[:assignment_id]
                assg
              end

              option
            end

            js_env({
                     CHOOSE_MASTERY_PATH_DATA: {
                       options:,
                       selectedOption: rule[:selected_set_id],
                       courseId: @context.id,
                       moduleId: item.context_module.id,
                       itemId: id
                     }
                   })

            css_bundle :choose_mastery_path
            js_bundle :choose_mastery_path

            @page_title = join_title(t("Choose Assignment Set"), @context.name)

            return render html: "", layout: true
          end
        end
      end
      render status: :not_found, template: "shared/errors/404_message"
    end
  end

  def items_html
    unless @context.account.feature_enabled?(:modules_perf)
      return render status: :not_found, template: "shared/errors/404_message"
    end

    if authorized_action(@context, @current_user, :read)
      @module = @context.modules_visible_to(@current_user).find_by(id: params[:context_module_id])
      return render status: :not_found, template: "shared/errors/404_message" unless @module

      @items = load_content_tags(@module, @current_user)
      @items_count = @items.count
      unless params[:no_pagination]
        @items = Api.paginate(@items, self, course_context_module_context_modules_items_html_url)
      end
      load_menu_tools
      load_permissions

      render template: "context_modules/items_html", layout: false
    end
  end

  def module_html
    unless @context.account.feature_enabled?(:modules_perf)
      return render status: :not_found, template: "shared/errors/404_message"
    end

    if authorized_action(@context, @current_user, :read)
      @module = @context.modules_visible_to(@current_user).find_by(id: params[:context_module_id])
      return render status: :not_found, template: "shared/errors/404_message" unless @module

      @modules = [@module]
      load_module_show_setting
      load_menu_tools
      load_permissions

      render template: "context_modules/module_html", layout: false
    end
  end

  def item_redirect
    if authorized_action(@context, @current_user, :read)
      @tag = @context.context_module_tags.not_deleted.find(params[:id])

      if !(@tag.unpublished? || @tag.context_module.unpublished?) || authorized_action(@tag.context_module, @current_user, :view_unpublished_items)
        reevaluate_modules_if_locked(@tag)
        @progression = @tag.context_module.evaluate_for(@current_user) if @tag.context_module
        @progression.uncollapse! if @progression&.collapsed?
        content_tag_redirect(@context, @tag, :context_context_modules_url, :modules)
      end
    end
  end

  def item_redirect_mastery_paths
    @tag = @context.context_module_tags.not_deleted.find(params[:id])

    type_controllers = {
      assignment: "assignments",
      quiz: "quizzes/quizzes",
      discussion_topic: "discussion_topics",
      "lti-quiz": "assignments"
    }

    if @tag
      if authorized_action(@tag.content, @current_user, :update)
        controller = type_controllers[@tag.content_type_class.to_sym]

        if controller.present?
          redirect_to url_for(
            controller:,
            action: "edit",
            id: @tag.content_id,
            anchor: "mastery-paths-editor",
            return_to: params[:return_to]
          )
        else
          render status: :not_found, template: "shared/errors/404_message"
        end
      end
    else
      render status: :not_found, template: "shared/errors/404_message"
    end
  end

  def module_redirect
    if authorized_action(@context, @current_user, :read)
      @module = @context.context_modules.not_deleted.find(params[:context_module_id])
      @tags = @module.content_tags_visible_to(@current_user)
      if params[:last]
        @tags.pop while @tags.last && @tags.last.content_type == "ContextModuleSubHeader"
      else
        @tags.shift while @tags.first && @tags.first.content_type == "ContextModuleSubHeader"
      end
      @tag = params[:last] ? @tags.last : @tags.first
      unless @tag
        flash[:notice] = t "module_empty", %(There are no items in the module "%{module}"), module: @module.name
        redirect_to named_context_url(@context, :context_context_modules_url, anchor: "module_#{@module.id}")
        return
      end

      reevaluate_modules_if_locked(@tag)
      @progression = @tag.context_module.evaluate_for(@current_user) if @tag&.context_module
      @progression.uncollapse! if @progression&.collapsed?
      content_tag_redirect(@context, @tag, :context_context_modules_url)
    end
  end

  def reevaluate_modules_if_locked(tag)
    # if the object is locked for this user, reevaluate all the modules and clear the cache so it will be checked again when loaded
    if tag.content.respond_to?(:locked_for?)
      locked = tag.content.locked_for?(@current_user, context: @context)
      if locked
        @context.context_modules.active.each { |m| m.evaluate_for(@current_user) }
      end
    end
  end

  def create
    if authorized_action(@context.context_modules.temp_record, @current_user, :create)
      @module = @context.context_modules.build
      @module.workflow_state = "unpublished"
      @module.attributes = context_module_params
      respond_to do |format|
        if @module.save
          format.html { redirect_to named_context_url(@context, :context_context_modules_url) }
          format.json { render json: @module.as_json(include: :content_tags, methods: :workflow_state, permissions: { user: @current_user, session: }) }
        else
          format.html
          format.json { render json: @module.errors, status: :bad_request }
        end
      end
    end
  end

  def reorder
    if authorized_action(@context.context_modules.temp_record, @current_user, :update)
      first_module = @context.context_modules.not_deleted.first

      # A hash where the key is the module id and the value is the module position
      order_before = @context.context_modules.not_deleted.pluck(:id, :position).to_h

      first_module.update_order(params[:order].split(","))
      # Need to invalidate the ordering cache used by context_module.rb
      @context.touch

      # I'd like to get rid of this saving every module, but we have to
      # update the list of prerequisites since a reorder can cause
      # prerequisites to no longer be valid
      @modules = @context.context_modules.not_deleted.to_a
      @modules.each do |m|
        m.updated_at = Time.zone.now
        m.save_without_touching_context
        Canvas::LiveEvents.module_updated(m) if m.position != order_before[m.id]
      end
      # Update course paces if enabled
      if @context.enable_course_paces
        @context.course_paces.published.find_each(&:create_publish_progress)
      end
      @context.touch

      # # Background this, not essential that it happen right away
      # ContextModule.delay.update_tag_order(@context)
      render json: @modules.map { |m| m.as_json(include: :content_tags, methods: :workflow_state) }
    end
  end

  def content_tag_assignment_data
    if authorized_action(@context, @current_user, :read)
      info = {}

      all_tags = GuardRail.activate(:secondary) do
        if context.account.feature_enabled?(:modules_perf) && params[:context_module_id]
          @module = @context.modules_visible_to(@current_user).find_by(id: params[:context_module_id])
          return render json: {}, status: :not_found unless @module

          @context.visible_module_items_by_module(@current_user, @module).to_a
        else
          @context.module_items_visible_to(@current_user).to_a
        end
      end
      user_is_admin = @context.grants_right?(@current_user, session, :read_as_admin)

      all_tags.each_slice(1000) do |tags|
        ActiveRecord::Associations.preload(tags, content: [:context, :external_tool_tag])
      end

      preload_assignments_and_quizzes(all_tags, user_is_admin)

      assignment_ids = []
      quiz_ids = []
      all_tags.each do |tag|
        if tag.can_have_assignment? && tag.assignment
          assignment_ids << tag.assignment.id
        elsif tag.content_type_quiz?
          quiz_ids << tag.content.id
        end
      end

      submitted_assignment_ids = if @current_user && assignment_ids.any?
                                   assignments_key = Digest::SHA256.hexdigest(assignment_ids.sort.join(","))
                                   Rails.cache.fetch_with_batched_keys("submitted_assignment_ids/#{assignments_key}",
                                                                       batch_object: @current_user,
                                                                       batched_keys: :submissions) do
                                     @current_user.submissions.shard(@context.shard)
                                                  .having_submission.where(assignment_id: assignment_ids).pluck(:assignment_id)
                                   end
                                 end
      if @current_user && quiz_ids.any?
        submitted_quiz_ids = @current_user.quiz_submissions.shard(@context.shard)
                                          .completed.where(quiz_id: quiz_ids).pluck(:quiz_id)
      end
      submitted_assignment_ids ||= []
      submitted_quiz_ids ||= []
      all_tags.each do |tag|
        info[tag.id] = if tag.can_have_assignment? && tag.assignment
                         tag.assignment.context_module_tag_info(@current_user,
                                                                @context,
                                                                user_is_admin:,
                                                                has_submission: submitted_assignment_ids.include?(tag.assignment.id))
                       elsif tag.content_type_quiz?
                         tag.content.context_module_tag_info(@current_user,
                                                             @context,
                                                             user_is_admin:,
                                                             has_submission: submitted_quiz_ids.include?(tag.content.id))
                       else
                         { points_possible: nil, due_date: nil }
                       end
        info[tag.id][:todo_date] = tag.content && tag.content[:todo_date]

        if tag.try(:assignment).try(:external_tool_tag).try(:external_data).try(:[], "key") == "https://canvas.instructure.com/lti/mastery_connect_assessment"
          info[tag.id][:mc_objectives] = tag.assignment.external_tool_tag.external_data["objectives"]
        end
      end
      render json: info
    end
  end

  def content_tag_estimated_duration_data
    if authorized_action(@context, @current_user, :read)
      info = {}
      all_tags = GuardRail.activate(:secondary) do
        if context.account.feature_enabled?(:modules_perf) && params[:context_module_id]
          @module = @context.modules_visible_to(@current_user).find_by(id: params[:context_module_id])
          return render json: {}, status: :not_found unless @module

          @context.visible_module_items_by_module(@current_user, @module).to_a
        else
          @context.module_items_visible_to(@current_user).to_a
        end
      end

      all_tags.each do |tag|
        info[tag.context_module_id] ||= {}
        info[tag.context_module_id][tag.id] = { estimated_duration_minutes: tag.estimated_duration_minutes, can_set_estimated_duration: tag.can_set_estimated_duration }
      end
      render json: info
    end
  end

  def content_tag_master_course_data
    if authorized_action(@context, @current_user, :read_as_admin)
      info = {}
      is_child_course = MasterCourses::ChildSubscription.is_child_course?(@context)
      is_master_course = MasterCourses::MasterTemplate.is_master_course?(@context)

      if is_child_course || is_master_course
        tag_ids = GuardRail.activate(:secondary) do
          if context.account.feature_enabled?(:modules_perf) && params[:context_module_id]
            @module = @context.modules_visible_to(@current_user).find_by(id: params[:context_module_id])
            return render json: { tag_restrictions: {} }, status: :not_found unless @module

            tag_scope = @context.visible_module_items_by_module(@current_user, @module)
          else
            tag_scope = @context.module_items_visible_to(@current_user)
          end

          tag_scope = tag_scope.where(content_type: %w[Assignment Attachment DiscussionTopic Quizzes::Quiz WikiPage])
          tag_scope = tag_scope.where(id: params[:tag_id]) if params[:tag_id]
          tag_scope.pluck(:id)
        end
        restriction_info = {}
        if tag_ids.any?
          restriction_info = if is_child_course
                               MasterCourses::MasterContentTag.fetch_module_item_restrictions_for_child(tag_ids)
                             else
                               MasterCourses::MasterContentTag.fetch_module_item_restrictions_for_master(tag_ids)
                             end
        end
        info[:tag_restrictions] = restriction_info
      end
      render json: info
    end
  end

  def prerequisites_needing_finishing_for(mod, progression, before_tag = nil)
    tags = mod.content_tags_visible_to(@current_user)
    pres = []
    tags.each do |tag|
      next unless (req = (mod.completion_requirements || []).detect { |r| r[:id] == tag.id })

      progression.requirements_met ||= []
      next unless progression.requirements_met.none? { |r| r[:id] == req[:id] && r[:type] == req[:type] } &&
                  (!before_tag || tag.position <= before_tag.position)

      pre = {
        url: named_context_url(@context, :context_context_modules_item_redirect_url, tag.id),
        id: tag.id,
        context_module_id: mod.id,
        title: tag.title
      }
      pre[:requirement] = req
      pre[:requirement_description] = ContextModule.requirement_description(req)
      pre[:available] = !progression.locked? && (!mod.require_sequential_progress || tag.position <= progression.current_position)
      pres << pre
    end
    pres
  end
  protected :prerequisites_needing_finishing_for

  def content_tag_prerequisites_needing_finishing
    type, id = ActiveRecord::Base.parse_asset_string params[:code]
    raise ActiveRecord::RecordNotFound if id == 0

    @tag = if type == "ContentTag"
             @context.context_module_tags.active.where(id:).first
           else
             @context.context_module_tags.active.where(context_module_id: params[:context_module_id], content_id: id, content_type: type).first
           end
    @module = @context.context_modules.active.find(params[:context_module_id])
    @progression = @module.evaluate_for(@current_user)
    @progression.current_position ||= 0 if @progression
    res = {}
    if !@progression
      # do nothing
    elsif @progression.locked?
      res[:locked] = true
      res[:modules] = []
      previous_modules = @context.context_modules.active.where("position<?", @module.position).ordered.to_a
      previous_modules.reverse!
      valid_previous_modules = []
      prereq_ids = @module.prerequisites.select { |p| p[:type] == "context_module" }.pluck(:id)
      previous_modules.each do |mod|
        if prereq_ids.include?(mod.id)
          valid_previous_modules << mod
          prereq_ids += mod.prerequisites.select { |p| p[:type] == "context_module" }.pluck(:id)
        end
      end
      valid_previous_modules.reverse!
      valid_previous_modules.each do |mod|
        prog = mod.evaluate_for(@current_user)
        next if prog.completed?

        res[:modules] << {
          id: mod.id,
          name: mod.name,
          prerequisites: prerequisites_needing_finishing_for(mod, prog),
          locked: prog.locked?
        }
      end
    elsif @module.require_sequential_progress && @progression.current_position && @tag&.position && @progression.current_position < @tag.position
      res[:locked] = true
      pres = prerequisites_needing_finishing_for(@module, @progression, @tag)
      res[:modules] = [{
        id: @module.id,
        name: @module.name,
        prerequisites: pres,
        locked: false
      }]
    else
      res[:locked] = false
    end
    render json: res
  end

  def collapse(mod, should_collapse)
    progression = mod.evaluate_for(@current_user)
    progression ||= ContextModuleProgression.new
    if value_to_boolean(should_collapse)
      progression.collapse!(skip_save: progression.new_record?)
    else
      progression.uncollapse!(skip_save: progression.new_record?)
    end
    progression
  end

  def toggle_collapse
    if authorized_action(@context, @current_user, :read)
      return unless params.key?(:collapse)

      @module = @context.modules_visible_to(@current_user).find(params[:context_module_id])
      progression = collapse(@module, params[:collapse])
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :context_context_modules_url) }
        format.json do
          if progression.collapsed
            render json: progression
          else
            # Preload content associations to prevent N+1 queries when rendering JSON
            content_tags = @module.content_tags_visible_to(@current_user)
            assignment_ids = content_tags.filter_map { |ct| ct.content_id if ct.content_type == "Assignment" }

            if assignment_ids.any?
              assignments = Assignment.where(id: assignment_ids).index_by(&:id)
              content_tags.each do |ct|
                if ct.content_type == "Assignment" && assignments[ct.content_id]
                  ct.association(:content).target = assignments[ct.content_id]
                end
              end
            end

            render json: content_tags
          end
        end
      end
    end
  end

  def toggle_collapse_all
    if authorized_action(@context, @current_user, :read)
      return unless params.key?(:collapse)

      @modules = @context.modules_visible_to(@current_user)
      @modules.each do |mod|
        collapse(mod, params[:collapse])
      end
    end
  end

  def show
    @module = @context.context_modules.not_deleted.find(params[:id])
    if authorized_action @module, @current_user, :read
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :context_context_modules_url, anchor: "module_#{params[:id]}") }
        format.json { render json: @module.content_tags_visible_to(@current_user) }
      end
    end
  end

  def reorder_items
    @module = @context.context_modules.not_deleted.find(params[:context_module_id])
    if authorized_action(@module, @current_user, :update)
      order = params[:order].split(",").map(&:to_i)
      tags = @context.context_module_tags.not_deleted.where(id: order)
      affected_module_ids = (tags.map(&:context_module_id) + [@module.id]).uniq.compact
      affected_items = []
      items = order.filter_map { |id| tags.detect { |t| t.id == id.to_i } }.uniq
      items.each_with_index do |item, idx|
        item.position = idx + 1
        item.context_module_id = @module.id
        next unless item.changed?

        item.skip_touch = true
        item.save
        affected_items << item
      end
      ContentTag.touch_context_modules(affected_module_ids)
      ContentTag.update_could_be_locked(affected_items)
      @context.touch
      @module.reload
      render json: @module.as_json(include: :content_tags, methods: :workflow_state, permissions: { user: @current_user, session: })
    end
  end

  def item_details
    if authorized_action(@context, @current_user, :read)
      # namespaced models are separated by : in the url
      code = params[:id].tr(":", "/").split("_")
      id = code.pop.to_i
      type = code.join("_").classify
      @modules = @context.modules_visible_to(@current_user)
      @tags = @context.context_module_tags.active.sort_by { |t| t.position ||= 999 }
      result = {}
      possible_tags = @tags.find_all { |t| t.content_type == type && t.content_id == id }
      if possible_tags.size > 1
        # if there's more than one tag for the item, but the caller didn't
        # specify which one they want, we don't want to return any information.
        # this way the module item prev/next links won't appear with misleading navigation info.
        if params[:module_item_id]
          result[:current_item] = possible_tags.detect { |t| t.id == params[:module_item_id].to_i }
        end
      else
        result[:current_item] = possible_tags.first
        unless result[:current_item]
          obj = @context.find_asset(params[:id], %i[attachment discussion_topic assignment quiz wiki_page content_tag])
          if obj.is_a?(ContentTag)
            result[:current_item] = @tags.detect { |t| t.id == obj.id }
          elsif (obj.is_a?(DiscussionTopic) && obj.assignment_id) ||
                (obj.is_a?(Quizzes::Quiz) && obj.assignment_id)
            result[:current_item] = @tags.detect { |t| t.content_type == "Assignment" && t.content_id == obj.assignment_id }
          end
        end
      end
      result[:current_item].try(:evaluate_for, @current_user)
      if result[:current_item]&.position
        result[:previous_item] = @tags.reverse.detect { |t| t.id != result[:current_item].id && t.context_module_id == result[:current_item].context_module_id && t.position && t.position <= result[:current_item].position && t.content_type != "ContextModuleSubHeader" }
        result[:next_item] = @tags.detect { |t| t.id != result[:current_item].id && t.context_module_id == result[:current_item].context_module_id && t.position && t.position >= result[:current_item].position && t.content_type != "ContextModuleSubHeader" }
        current_module = @modules.detect { |m| m.id == result[:current_item].context_module_id }
        if current_module
          result[:previous_module] = @modules.reverse.detect { |m| (m.position || 0) < (current_module.position || 0) }
          result[:next_module] = @modules.detect { |m| (m.position || 0) > (current_module.position || 0) }
        end
      end
      render json: result
    end
  end

  include ContextModulesHelper
  def add_item
    @module = @context.context_modules.not_deleted.find(params[:context_module_id])

    if authorized_action(@context, @current_user, %i[manage_course_content_add manage_course_content_edit])
      params[:item][:link_settings] = launch_dimensions
      @tag = @module.add_item(params[:item])
      unless @tag&.valid?
        body = @tag.nil? ? { error: "Could not find item to tag" } : @tag.errors
        return render json: body, status: :bad_request
      end
      update_module_link_default_tab(@tag)
      json = @tag.as_json
      json["content_tag"].merge!(
        publishable: module_item_publishable?(@tag),
        published: @tag.published?,
        publishable_id: module_item_publishable_id(@tag),
        unpublishable: module_item_unpublishable?(@tag),
        publish_at: module_item_publish_at(@tag),
        graded: @tag.graded?,
        content_details: content_details(@tag, @current_user),
        assignment_id: @tag.assignment.try(:id),
        is_checkpointed: @tag.assignment.try(:has_sub_assignments),
        is_cyoe_able: cyoe_able?(@tag),
        is_duplicate_able: @tag.duplicate_able?,
        can_manage_assign_to: @tag.content&.grants_right?(@current_user, session, :manage_assign_to)
      )
      @context.touch
      render json:
    end
  end

  def remove_item
    @tag = @context.context_module_tags.not_deleted.find(params[:id])
    if authorized_action(@tag.context_module, @current_user, :update)
      @module = @tag.context_module
      @tag.destroy
      render json: @tag
    end
  end

  def create_estimated_duration(reference, duration)
    unless reference.can_set_estimated_duration
      return nil
    end

    reference_mapping = {
      "Assignment" => :assignment_id,
      "Quizzes::Quiz" => :quiz_id,
      "WikiPage" => :wiki_page_id,
      "DiscussionTopic" => :discussion_topic_id,
      "Attachment" => :attachment_id
    }

    reference_type = reference.respond_to?(:content_type) ? reference.content_type : reference.class.name
    reference_key = reference_mapping[reference_type] ||= :content_tag_id

    content_id = reference.tap do |ref|
      break ref.id if reference_key == :content_tag_id
      break ref.content_id if ref.respond_to?(:content_id)

      break ref.id
    end

    estimated_duration = EstimatedDuration.new(reference_key => content_id, :duration => duration)

    if estimated_duration.save
      estimated_duration
    else
      nil
    end
  end

  def get_estimated_duration(minutes)
    return nil if minutes.zero?

    "PT#{minutes}M"
  end

  def update_item
    @tag = @context.context_module_tags.not_deleted.find(params[:id])
    if authorized_action(@tag.context_module, @current_user, :update)
      @tag.title = params[:content_tag][:title] if params[:content_tag] && params[:content_tag][:title]
      if LINK_ITEM_TYPES.include?(@tag.content_type) && params[:content_tag] && params[:content_tag][:url]
        @tag.url = params[:content_tag][:url]
        @tag.reassociate_external_tool = true
      end
      @tag.indent = params[:content_tag][:indent] if params[:content_tag] && params[:content_tag][:indent] && !@context.horizon_course?
      @tag.new_tab = params[:content_tag][:new_tab] if params[:content_tag] && params[:content_tag][:new_tab]

      if @context.horizon_course?
        duration = get_estimated_duration(params[:content_tag][:estimated_duration_minutes].to_i)

        if duration.nil?
          @tag.estimated_duration&.destroy!
        elsif @tag.estimated_duration
          @tag.estimated_duration.update(duration:)
        else
          @tag.estimated_duration = create_estimated_duration(@tag, duration)
        end
      end

      unless @tag.save
        return render json: @tag.errors, status: :bad_request
      end

      update_module_link_default_tab(@tag)
      @tag.update_asset_name!(@current_user) if params[:content_tag][:title]
      render json: @tag
    end
  end

  def progressions
    if authorized_action(@context, @current_user, :read)
      if request.format == :json
        base_modules_query = @context.context_modules.active
        if context.account.feature_enabled?(:modules_perf) && params[:context_module_id]
          base_modules_query = base_modules_query.where(id: params[:context_module_id])
          return render json: [], status: :not_found if base_modules_query.empty?
        end
        if @context.grants_right?(@current_user, session, :view_all_grades)
          if params[:user_id] && (@user = @context.students.find(params[:user_id]))
            @progressions = base_modules_query.map { |m| m.evaluate_for(@user) }
          elsif @context.large_roster
            @progressions = []
          else
            context_module_ids = base_modules_query.pluck(:id)
            @progressions = ContextModuleProgression.where(context_module_id: context_module_ids).each(&:evaluate)
          end
        elsif @context.grants_right?(@current_user, session, :participate_as_student)
          @progressions = base_modules_query.order(:id).map { |m| m.evaluate_for(@current_user) }
        else
          # module progressions don't apply, but unlock_at still does
          @progressions = base_modules_query.order(:id).map do |m|
            { context_module_progression: { context_module_id: m.id,
                                            workflow_state: (m.to_be_unlocked ? "locked" : "unlocked"),
                                            requirements_met: [],
                                            incomplete_requirements: [] } }
          end
        end
        render json: @progressions
      elsif !@context.grants_right?(@current_user, session, :view_all_grades)
        @restrict_student_list = true
        student_ids = @context.observer_enrollments.for_user(@current_user).map(&:associated_user_id)
        student_ids << @current_user.id if @context.user_is_student?(@current_user)
        students = UserSearch.scope_for(@context, @current_user, { enrollment_type: "student" }).where(id: student_ids)
        @visible_students = students.map { |u| user_json(u, @current_user, session) }
      end
    end
  end

  def update
    @module = @context.context_modules.not_deleted.find(params[:id])
    if authorized_action(@module, @current_user, :update)
      if params[:publish]
        @module.publish
        @module.publish_items!
      elsif params[:unpublish]
        @module.unpublish
      end
      if @module.update(context_module_params)
        json = @module.as_json(include: :content_tags, methods: :workflow_state, permissions: { user: @current_user, session: })
        json["context_module"]["relock_warning"] = true if @module.relock_warning?
        render json:
      else
        render json: @module.errors, status: :bad_request
      end
    end
  end

  def destroy
    @module = @context.context_modules.not_deleted.find(params[:id])
    if authorized_action(@module, @current_user, :delete)
      @module.destroy
      respond_to do |format|
        format.html { redirect_to named_context_url(@context, :context_context_modules_url) }
        format.json { render json: @module.as_json(methods: :workflow_state) }
      end
    end
  end

  private

  def preload_assignments_and_quizzes(tags, user_is_admin)
    assignment_tags = tags.select(&:can_have_assignment?)
    return unless assignment_tags.any?

    content_with_assignments = assignment_tags
                               .select { |ct| ct.content_type != "Assignment" && ct.content.assignment_id }.map(&:content)
    ActiveRecord::Associations.preload(content_with_assignments, :assignment) if content_with_assignments.any?
    DatesOverridable.preload_override_data_for_objects(content_with_assignments.map(&:assignment))
    override_preload_types = %w[Assignment Quizzes::Quiz WikiPage DiscussionTopic].freeze
    DatesOverridable.preload_override_data_for_objects(tags.select { |ct| override_preload_types.include?(ct.content_type) }.map(&:content))

    if user_is_admin && should_preload_override_data?
      assignments = assignment_tags.filter_map(&:assignment)
      plain_quizzes = assignment_tags.select { |ct| ct.content.is_a?(Quizzes::Quiz) && !ct.content.assignment }.map(&:content)
      preload_has_too_many_overrides(assignments, :assignment_id)
      preload_has_too_many_overrides(plain_quizzes, :quiz_id)

      sub_assignments = []
      if @context.discussion_checkpoints_enabled?
        ActiveRecord::Associations.preload(assignments, :sub_assignments) if assignments.any?
        sub_assignments = assignments.flat_map(&:sub_assignments)
        preload_has_too_many_overrides(sub_assignments, :assignment_id)
      end

      overrideables = (assignments + plain_quizzes + sub_assignments).reject(&:has_too_many_overrides)

      if overrideables.any?
        ActiveRecord::Associations.preload(overrideables, :assignment_overrides)
        overrideables.each { |o| o.has_no_overrides = true if o.assignment_overrides.empty? }
      end
    end
  end

  def should_preload_override_data?
    key = ["preloaded_module_override_data2", @context.global_asset_string, @current_user.cache_key(:enrollments), @current_user.cache_key(:groups)].cache_key
    # if the user has been touched we should preload all of the overrides because it's almost certain we'll need them all
    if Rails.cache.read(key)
      false
    else
      Rails.cache.write(key, true)
      true
    end
  end

  def preload_has_too_many_overrides(assignments_or_quizzes, override_column)
    # find the assignments/quizzes with too many active overrides and mark them as such
    if assignments_or_quizzes.any?
      ids = AssignmentOverride.active.where(override_column => assignments_or_quizzes)
                              .group(override_column).having("COUNT(*) > ?", Api::V1::Assignment::ALL_DATES_LIMIT)
                              .active.pluck(override_column)
      if ids.any?
        assignments_or_quizzes.each { |o| o.has_too_many_overrides = true if ids.include?(o.id) }
      end
    end
  end

  def context_module_params
    params.require(:context_module).permit(:name,
                                           :unlock_at,
                                           :require_sequential_progress,
                                           :publish_final_grade,
                                           :requirement_count,
                                           completion_requirements: strong_anything,
                                           prerequisites: strong_anything)
  end

  def update_module_link_default_tab(tag)
    if LINK_ITEM_TYPES.include?(tag.content_type)
      current_value = @current_user.get_preference(:module_links_default_new_tab)
      if current_value && !tag.new_tab
        @current_user.set_preference(:module_links_default_new_tab, false)
      elsif !current_value && tag.new_tab
        @current_user.set_preference(:module_links_default_new_tab, true)
      end
    end
  end

  def launch_dimensions
    return nil unless (iframe = params[:item][:iframe])

    {
      selection_width: iframe[:width],
      selection_height: iframe[:height]
    }
  end
end
