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

require_relative "../../import_helper"

describe Course do
  describe "#import_content" do
    before(:once) do
      @course = course_factory
      @course.root_account.settings[:provision] = { "lti" => "lti url" }
      @course.root_account.save!
      @course
    end

    it "imports a whole json file" do
      local_storage!

      # TODO: pull this out into smaller tests... right now I'm using
      # the whole example JSON from Bracken because the formatting is
      # somewhat in flux
      json = File.read(File.join(IMPORT_JSON_DIR, "import_from_migration.json"))
      data = JSON.parse(json).with_indifferent_access
      data["all_files_export"] = {
        "file_path" => File.join(IMPORT_JSON_DIR, "import_from_migration_small.zip")
      }
      migration = ContentMigration.create!(context: @course, started_at: Time.zone.now)
      allow(migration).to receive(:canvas_import?).and_return(true)

      params = { copy: {
        topics: { "1864019689002" => true, "1865116155002" => true },
        announcements: { "4488523052421" => true },
        files: { "1865116527002" => true, "1865116044002" => true, "1864019880002" => true, "1864019921002" => true },
        rubrics: { "4469882249231" => true },
        events: {},
        modules: { "1864019977002" => true, "1865116190002" => true },
        assignments: {
          "1865116014002" => true,
          "1865116155002" => true,
          "4407365899221" => true,
          "4469882339231" => true
        },
        outline_folders: { "1865116206002" => true, "1865116207002" => true },
        quizzes: { "1865116175002" => true },
        all_course_outline: true,
        all_groups: true,
        shift_dates: "1",
        old_start_date: "Jan 23, 2009",
        old_end_date: "Apr 10, 2009",
        new_start_date: "Jan 3, 2011",
        new_end_date: "Apr 13, 2011"
      } }.with_indifferent_access
      migration.migration_ids_to_import = params

      expect(migration).to receive(:trigger_live_events!).once

      # tool profile tests
      expect(Importers::ToolProfileImporter).to receive(:process_migration)

      Importers::CourseContentImporter.import_content(@course, data, params, migration)
      @course.reload

      # discussion topic tests
      expect(@course.discussion_topics.length).to eq(3)
      migration_ids = %w[1864019689002 1865116155002 4488523052421].sort
      added_migration_ids = @course.discussion_topics.map(&:migration_id).uniq.sort
      expect(added_migration_ids).to eq(migration_ids)
      topic = @course.discussion_topics.where(migration_id: "1864019689002").first
      expect(topic).not_to be_nil
      expect(topic.title).to eq("Post here for group events, etc.")
      expect(topic.discussion_entries).to be_empty
      topic = @course.discussion_topics.where(migration_id: "1865116155002").first
      expect(topic).not_to be_nil
      expect(topic.assignment).not_to be_nil

      # quizzes
      expect(@course.quizzes.length).to eq(1)
      quiz = @course.quizzes.first
      quiz.migration_id = "1865116175002"
      expect(quiz.title).to eq("Orientation Quiz")

      # wiki pages tests
      migration_ids = ["1865116206002", "1865116207002"].sort
      added_migration_ids = @course.wiki_pages.map(&:migration_id).uniq.sort
      expect(added_migration_ids).to eq(migration_ids)
      expect(@course.wiki_pages.length).to eq(migration_ids.length)
      # front page
      page = @course.wiki.front_page
      expect(page).not_to be_nil
      expect(page.migration_id).to eq("1865116206002")
      expect(page.body).not_to be_nil
      expect(page.body.scan("<li>").length).to eq(4)
      expect(page.body).to match(/Orientation/)
      expect(page.body).to match(/Orientation Quiz/)
      file = @course.attachments.where(migration_id: "1865116527002").first
      expect(file).not_to be_nil
      re = Regexp.new("\\/courses\\/#{@course.id}\\/files\\/#{file.id}\\/preview")
      expect(page.body).to match(re)

      # assignment tests
      @course.reload
      expect(@course.assignments.length).to eq 4
      expect(@course.assignments.map(&:migration_id).sort).to(
        eq(%w[1865116155002 1865116014002 4407365899221 4469882339231].sort)
      )
      # assignment with due date
      assignment = @course.assignments.where(migration_id: "1865116014002").first
      expect(assignment).not_to be_nil
      expect(assignment.title).to eq("Concert Review Assignment")
      expect(assignment.description).to match(Regexp.new("USE THE TEXT BOX!  DO NOT ATTACH YOUR ASSIGNMENT!!"))
      # The old due date (Fri Mar 27 23:55:00 -0600 2009) should have been adjusted to new time frame
      expect(assignment.due_at.year).to eq 2011
      # overrides
      expect(assignment.assignment_overrides.count).to eq 1
      expect(assignment.assignment_overrides.first.due_at.year).to eq 2011

      # discussion topic assignment
      assignment = @course.assignments.where(migration_id: "1865116155002").first
      expect(assignment).not_to be_nil
      expect(assignment.title).to eq("Introduce yourself!")
      expect(assignment.points_possible).to eq(10.0)
      expect(assignment.discussion_topic).not_to be_nil
      # assignment with rubric
      assignment = @course.assignments.where(migration_id: "4469882339231").first
      expect(assignment).not_to be_nil
      expect(assignment.title).to eq("Rubric assignment")
      expect(assignment.rubric).not_to be_nil
      expect(assignment.rubric.migration_id).to eq("4469882249231")
      # assignment with file
      assignment = @course.assignments.where(migration_id: "4407365899221").first
      expect(assignment).not_to be_nil
      expect(assignment.title).to eq("new assignment")
      file = @course.attachments.where(migration_id: "1865116527002").first
      expect(file).not_to be_nil
      expect(assignment.description).to match(Regexp.new("/files/#{file.id}/download"))

      # calendar events
      expect(@course.calendar_events).to be_empty

      # rubrics
      expect(@course.rubrics.length).to eq(1)
      rubric = @course.rubrics.first
      expect(rubric.data.length).to eq(3)
      expect(rubric.association_count).to eq 1
      # Spelling
      criterion = rubric.data[0].with_indifferent_access
      expect(criterion["description"]).to eq("Spelling")
      expect(criterion["points"]).to eq(15.0)
      expect(criterion["ratings"].length).to eq(3)
      expect(criterion["ratings"][0]["points"]).to eq(15.0)
      expect(criterion["ratings"][0]["description"]).to eq("Exceptional - fff")
      expect(criterion["ratings"][1]["points"]).to eq(10.0)
      expect(criterion["ratings"][1]["description"]).to eq("Meet Expectations - asdf")
      expect(criterion["ratings"][2]["points"]).to eq(5.0)
      expect(criterion["ratings"][2]["description"]).to eq("Need Improvement - rubric entry text")

      # Grammar
      criterion = rubric.data[1]
      expect(criterion["description"]).to eq("Grammar")
      expect(criterion["points"]).to eq(15.0)
      expect(criterion["ratings"].length).to eq(3)
      expect(criterion["ratings"][0]["points"]).to eq(15.0)
      expect(criterion["ratings"][0]["description"]).to eq("Exceptional")
      expect(criterion["ratings"][1]["points"]).to eq(10.0)
      expect(criterion["ratings"][1]["description"]).to eq("Meet Expectations")
      expect(criterion["ratings"][2]["points"]).to eq(5.0)
      expect(criterion["ratings"][2]["description"]).to eq("Need Improvement - you smell")

      # Style
      criterion = rubric.data[2]
      expect(criterion["description"]).to eq("Style")
      expect(criterion["points"]).to eq(15.0)
      expect(criterion["ratings"].length).to eq(3)
      expect(criterion["ratings"][0]["points"]).to eq(15.0)
      expect(criterion["ratings"][0]["description"]).to eq("Exceptional")
      expect(criterion["ratings"][1]["points"]).to eq(10.0)
      expect(criterion["ratings"][1]["description"]).to eq("Meet Expectations")
      expect(criterion["ratings"][2]["points"]).to eq(5.0)
      expect(criterion["ratings"][2]["description"]).to eq("Need Improvement")

      # groups
      expect(@course.groups.length).to eq(2)

      # files
      expect(@course.attachments.length).to eq(4)
      @course.attachments.each do |f|
        expect(File).to exist(f.full_filename)
      end
      file = @course.attachments.where(migration_id: "1865116044002").first
      expect(file).not_to be_nil
      expect(file.filename).to eq("theatre_example.htm")
      expect(file.folder.full_name).to eq("course files/Writing Assignments/Examples")
      file = @course.attachments.where(migration_id: "1864019880002").first
      expect(file).not_to be_nil
      expect(file.filename).to eq("dropbox.zip")
      expect(file.folder.full_name).to eq("course files/Course Content/Orientation/WebCT specific and old stuff")

      expect(migration.migration_settings[:attachment_path_id_lookup]).to eq(
        {
          "Course Content/Orientation/Ins and Outs/Eres directions.htm" => @course.attachments.find_by(display_name: "Eres directions.htm").migration_id,
          "Course Content/Orientation/WebCT specific and old stuff/dropbox.zip" => file.migration_id,
          "Pictures/banner_kandinsky.jpg" => @course.attachments.find_by(display_name: "banner_kandinsky.jpg").migration_id,
          "Writing Assignments/Examples/theatre_example.htm" => @course.attachments.find_by(display_name: "theatre_example.htm").migration_id,
        }
      )
    end

    def build_migration(import_course, params, copy_options = {})
      migration = ContentMigration.create!(context: import_course)
      migration.migration_settings[:migration_ids_to_import] = params
      migration.migration_settings[:copy_options] = copy_options
      migration.save!
      migration
    end

    def setup_import(import_course, filename, migration)
      json = File.read(File.join(IMPORT_JSON_DIR, filename))
      data = JSON.parse(json).with_indifferent_access
      Importers::CourseContentImporter.import_content(
        import_course,
        data,
        migration.migration_settings[:migration_ids_to_import],
        migration
      )
    end

    it "does not duplicate assessment questions in question banks" do
      params = { copy: { "everything" => true } }
      migration = build_migration(@course, params)
      setup_import(@course, "assessments.json", migration)

      aqb1 = @course.assessment_question_banks.where(migration_id: "i05dab0b3d55dae214bd0c4787bd6d20f").first
      expect(aqb1.assessment_questions.count).to eq 3
      aqb2 = @course.assessment_question_banks.where(migration_id: "iaac763df0de1199ef143b2ab8f237e76").first
      expect(aqb2.assessment_questions.count).to eq 2
      expect(migration.workflow_state).to eq("imported")
    end

    it "does not create assessment question banks if they are not selected" do
      params = { "copy" => { "assessment_question_banks" => { "i05dab0b3d55dae214bd0c4787bd6d20f" => true },
                             "quizzes" => { "i7ed12d5eade40d9ee8ecb5300b8e02b2" => true,
                                            "ife86eb19e30869506ee219b17a6a1d4e" => true } } }

      migration = build_migration(@course, params)
      setup_import(@course, "assessments.json", migration)

      expect(@course.assessment_question_banks.count).to eq 1
      aqb1 = @course.assessment_question_banks.where(migration_id: "i05dab0b3d55dae214bd0c4787bd6d20f").first
      expect(aqb1.assessment_questions.count).to eq 3
      expect(@course.assessment_questions.count).to eq 3

      expect(@course.quizzes.count).to eq 2
      quiz1 = @course.quizzes.where(migration_id: "i7ed12d5eade40d9ee8ecb5300b8e02b2").first
      quiz1.quiz_questions.preload(:assessment_question).each { |qq| expect(qq.assessment_question).not_to be_nil }

      quiz2 = @course.quizzes.where(migration_id: "ife86eb19e30869506ee219b17a6a1d4e").first
      quiz2.quiz_questions.preload(:assessment_question).each { |qq| expect(qq.assessment_question).to be_nil } # since the bank wasn't brought in
      expect(migration.workflow_state).to eq("imported")
    end

    it "locks announcements if 'lock_all_annoucements' setting is true" do
      @course.update_attribute(:lock_all_announcements, true)
      params = { "copy" => { "announcements" => { "4488523052421" => true } } }
      migration = build_migration(@course, params, all_course_settings: true)
      setup_import(@course, "announcements.json", migration)

      ann = @course.announcements.first
      expect(ann).to be_locked
      expect(migration.workflow_state).to eq("imported")
    end

    it "does not lock announcements if 'lock_all_annoucements' setting is false" do
      @course.update_attribute(:lock_all_announcements, false)
      params = { "copy" => { "announcements" => { "4488523052421" => true } } }
      migration = build_migration(@course, params, all_course_settings: true)
      setup_import(@course, "announcements.json", migration)

      ann = @course.announcements.first
      expect(ann).to_not be_locked
      expect(migration.workflow_state).to eq("imported")
    end

    it "runs SubmissionLifecycleManager never if no assignments are imported" do
      params = { copy: { "everything" => true } }
      migration = build_migration(@course, params)
      @course.reload # seems to be holding onto saved_changes for some reason

      expect(SubmissionLifecycleManager).not_to receive(:recompute_course)
      setup_import(@course, "assessments.json", migration)
      expect(migration.workflow_state).to eq("imported")
    end

    it "runs SubmissionLifecycleManager once if assignments with dates are imported" do
      params = { copy: { "everything" => true } }
      migration = build_migration(@course, params)
      @course.reload

      expect(SubmissionLifecycleManager).to receive(:recompute_course).once
      json = File.read(File.join(IMPORT_JSON_DIR, "assignment.json"))
      @data = { "assignments" => JSON.parse(json) }.with_indifferent_access
      Importers::CourseContentImporter.import_content(
        @course, @data, migration.migration_settings[:migration_ids_to_import], migration
      )
      expect(migration.workflow_state).to eq("imported")
    end

    it "automatically restores assignment groups for object assignment types (i.e. topics/quizzes)" do
      params = { copy: { "assignments" => { "gf455e2add230724ba190bb20c1491aa9" => true } } }
      migration = build_migration(@course, params)
      setup_import(@course, "discussion_assignments.json", migration)
      a1 = @course.assignments.find_by(migration_id: "gf455e2add230724ba190bb20c1491aa9")
      a1.assignment_group.destroy!

      # import again but just the discus
      params = { copy: { "discussion_topics" => { "g8bacee869e70bf19cd6784db3efade7e" => true } } }
      migration = build_migration(@course, params)
      setup_import(@course, "discussion_assignments.json", migration)
      dt = @course.discussion_topics.find_by(migration_id: "g8bacee869e70bf19cd6784db3efade7e")
      expect(dt.reply_to_entry_required_count).to eq 2
      expect(dt.assignment.assignment_group).to eq a1.assignment_group
      expect(dt.assignment.assignment_group).to_not be_deleted
      expect(a1.reload).to be_deleted # didn't restore the previously deleted assignment too
    end

    context "when it is a Quizzes.Next import process" do
      let(:migration) do
        params = { copy: { "everything" => true } }
        build_migration(@course, params)
      end

      before do
        allow(migration).to receive(:quizzes_next_import_process?).and_return(true)
      end

      it "does not set workflow_state to imported" do
        setup_import(@course, "assessments.json", migration)
        expect(migration.workflow_state).not_to eq("imported")
      end
    end

    describe "content migration workflow_state" do
      subject { setup_import(@course, "assessments.json", migration) }

      let(:migration) { build_migration(@course, copy: { "everything" => true }) }

      it "set workflow_state to imported" do
        subject
        expect(migration.workflow_state).to eq("imported")
      end

      context "when the migration_type is common_cartridge_importer" do
        before do
          migration.migration_type = "common_cartridge_importer"
        end

        it "set workflow_state to imported" do
          subject
          expect(migration.workflow_state).to eq("imported")
        end

        context "when common_cartridge_qti_new_quizzes_import_enabled? is true" do
          before do
            Account.site_admin.enable_feature!(:common_cartridge_qti_new_quizzes_import)
            migration.context.root_account.enable_feature!(:new_quizzes_migration)
          end

          it "does not set workflow_state to imported" do
            subject
            expect(migration.workflow_state).not_to eq("imported")
          end
        end
      end

      context "when the migration_type is canvas_cartridge_importer" do
        before do
          migration.migration_type = "canvas_cartridge_importer"
        end

        it "set workflow_state to imported" do
          subject
          expect(migration.workflow_state).to eq("imported")
        end

        context "when common_cartridge_qti_new_quizzes_import_enabled? is true" do
          before do
            Account.site_admin.enable_feature!(:common_cartridge_qti_new_quizzes_import)
            migration.context.root_account.enable_feature!(:new_quizzes_migration)
          end

          it "does not set workflow_state to imported" do
            subject
            expect(migration.workflow_state).not_to eq("imported")
          end
        end
      end

      context "when quizzes_next is enabled" do
        before { migration.context.enable_feature!(:quizzes_next) }

        it "set workflow_state to imported" do
          subject
          expect(migration.workflow_state).to eq("imported")
        end

        context "when import_quizzes_next is true in migration settings" do
          before do
            migration.migration_settings[:import_quizzes_next] = true
          end

          it "set workflow_state to imported" do
            subject
            expect(migration.workflow_state).not_to eq("imported")
          end
        end
      end
    end

    describe "default_post_policy" do
      let(:migration) do
        build_migration(@course, {}, all_course_settings: true)
      end

      it "sets the course to manually-posted when default_post_policy['post_manually'] is true" do
        import_data = { course: { default_post_policy: { post_manually: true } } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)

        expect(@course.default_post_policy).to be_post_manually
      end

      it "sets the course to auto-posted when default_post_policy['post_manually'] is false" do
        @course.default_post_policy.update!(post_manually: true)
        import_data = { course: { default_post_policy: { post_manually: false } } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)

        expect(@course.default_post_policy).not_to be_post_manually
      end

      it "does not update the course's post policy when default_post_policy['post_manually'] is missing" do
        @course.default_post_policy.update!(post_manually: true)
        import_data = { course: {} }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)

        expect(@course.default_post_policy).to be_post_manually
      end
    end

    describe "allow_final_grade_override" do
      let(:migration) { build_migration(@course, {}, all_course_settings: true) }

      it "is set to true when originally true" do
        import_data = { course: { allow_final_grade_override: "true" } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)

        # Specifically check the setting instead of the "allow_final_grade_override?"
        # method, since the method also checks for the feature flag (which isn't copied)
        expect(@course.allow_final_grade_override).to eq "true"
      end

      it "is set to false when originally false" do
        import_data = { course: { allow_final_grade_override: "false" } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)

        expect(@course.allow_final_grade_override).to eq "false"
      end
    end

    describe "enable_course_paces" do
      let(:migration) { build_migration(@course, {}, all_course_settings: true) }

      it "is set to true when originally true" do
        import_data = { course: { enable_course_paces: "true" } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)
        expect(@course.enable_course_paces).to be true
      end

      it "is set to false when originally false" do
        import_data = { course: { enable_course_paces: "false" } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)
        expect(@course.enable_course_paces).to be false
      end
    end

    describe "import_blueprint_settings" do
      it "runs blueprint importer if set to do so" do
        migration = ContentMigration.create!(context: @course, user: account_admin_user, source_course: @course, migration_settings: { import_blueprint_settings: true })
        expect(Importers::BlueprintSettingsImporter).to receive(:process_migration).once
        Importers::CourseContentImporter.import_content(@course, {}, nil, migration)
      end

      it "skips the blueprint importer if the user lacks proper permission" do
        usr = account_admin_user_with_role_changes(role_changes: { manage_master_courses: false })
        migration = ContentMigration.create!(context: @course, user: usr, source_course: @course, migration_settings: { import_blueprint_settings: true })
        expect(Importers::BlueprintSettingsImporter).not_to receive(:process_migration)
        Importers::CourseContentImporter.import_content(@course, {}, nil, migration)
      end
    end

    describe "conditional_release" do
      let(:migration) { build_migration(@course, {}, all_course_settings: true) }

      it "is set to true when originally true" do
        import_data = { course: { conditional_release: "true" } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)
        expect(@course.conditional_release).to be true
      end

      it "is set to false when originally false" do
        import_data = { course: { conditional_release: "false" } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)

        expect(@course.conditional_release).to be false
      end
    end

    describe "default_due_time" do
      let(:migration) { build_migration(@course, {}, all_course_settings: true) }

      it "is correctly imported" do
        import_data = { course: { default_due_time: "02:10:00" } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)
        expect(@course.default_due_time).to eq "02:10:00"
      end
    end

    describe "hide_sections_on_course_users_page" do
      let(:migration) { build_migration(@course, {}, all_course_settings: true) }

      before do
        @course.course_sections.create!
        @course.course_sections.create!
      end

      it "is set to true when originally true" do
        import_data = { course: { hide_sections_on_course_users_page: "true" } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)
        expect(@course.hide_sections_on_course_users_page).to be true
      end

      it "is set to false when originally false" do
        import_data = { course: { hide_sections_on_course_users_page: "false" } }.with_indifferent_access
        Importers::CourseContentImporter.import_content(@course, import_data, nil, migration)
        expect(@course.hide_sections_on_course_users_page).to be false
      end
    end
  end

  describe "shift_date_options" do
    it "defaults options[:time_zone] to the root account's time zone" do
      account = Account.default.sub_accounts.create!
      course_with_teacher(account:)
      @course.root_account.default_time_zone = "America/New_York"
      @course.start_at = 1.month.ago
      @course.conclude_at = 1.month.from_now
      options = Importers::CourseContentImporter.shift_date_options(@course, {})
      expect(options[:time_zone]).to eq ActiveSupport::TimeZone["Eastern Time (US & Canada)"]
    end
  end

  describe "shift_date" do
    it "rounds sanely" do
      course_factory
      @course.root_account.default_time_zone = Time.zone
      options = Importers::CourseContentImporter.shift_date_options(@course, {
                                                                      old_start_date: "2014-3-2",
                                                                      old_end_date: "2014-4-26",
                                                                      new_start_date: "2014-5-11",
                                                                      new_end_date: "2014-7-5"
                                                                    })
      unlock_at = Time.zone.local(2014, 3, 23, 0, 0)
      due_at    = Time.zone.local(2014, 3, 29, 23, 59)
      lock_at   = Time.zone.local(2014, 4, 1, 23, 59)

      new_unlock_at = Importers::CourseContentImporter.shift_date(unlock_at, options)
      new_due_at    = Importers::CourseContentImporter.shift_date(due_at, options)
      new_lock_at   = Importers::CourseContentImporter.shift_date(lock_at, options)

      expect(new_unlock_at).to eq Time.zone.local(2014, 6,  1, 0, 0)
      expect(new_due_at).to    eq Time.zone.local(2014, 6,  7, 23, 59)
      expect(new_lock_at).to   eq Time.zone.local(2014, 6, 10, 23, 59)
    end

    it "returns error when removing dates and new_sis_integrations is enabled" do
      course_factory
      @course.root_account.enable_feature!(:new_sis_integrations)
      @course.root_account.settings[:sis_syncing] = true
      @course.root_account.settings[:sis_require_assignment_due_date] = true
      @course.root_account.save!
      @course.account.enable_feature!(:new_sis_integrations)
      @course.account.settings[:sis_syncing] = true
      @course.account.settings[:sis_require_assignment_due_date] = true
      @course.account.save!

      assignment = @course.assignments.create!(due_at: 1.day.from_now)
      assignment.post_to_sis = true
      assignment.due_at = 1.day.from_now
      assignment.name = "lalala"
      assignment.save!

      migration = ContentMigration.create!(context: @course)
      migration.migration_ids_to_import = { copy: { copy_options: { all_assignments: "1" } } }.with_indifferent_access
      migration.migration_settings[:date_shift_options] = Importers::CourseContentImporter.shift_date_options(@course, { remove_dates: true })
      migration.add_imported_item(assignment)
      migration.source_course = @course
      migration.initiated_source = :manual
      migration.user = @user
      migration.save!

      Importers::CourseContentImporter.adjust_dates(@course, migration)
      expect(migration.warnings.length).to eq 1
      expect(migration.warnings[0]).to eq "Couldn't adjust dates on assignment lalala (ID #{assignment.id})"
    end

    describe "pre_date_shift_for_assignment_importing FF" do
      subject { Importers::CourseContentImporter.adjust_dates(course, migration) }

      let(:course) { course_model }
      let(:migration) do
        course.content_migrations.create!(
          migration_settings: {
            date_shift_options: {
              old_start_date: "2023-01-01",
              old_end_date: "2023-12-31",
              new_start_date: "2024-01-01",
              new_end_date: "2024-12-31"
            }
          }
        )
      end

      context "when the FF is enabled" do
        before do
          Account.site_admin.enable_feature!(:pre_date_shift_for_assignment_importing)
        end

        it "should not adjust Assignment dates" do
          expect(migration).not_to receive(:imported_migration_items_by_class).with(Assignment)
          subject
        end

        it "should not adjust Quiz::Quizzes dates" do
          expect(migration).not_to receive(:imported_migration_items_by_class).with(Quizzes::Quiz)
          subject
        end
      end

      context "when the FF is disabled" do
        before do
          allow(migration).to receive(:imported_migration_items_by_class).with(CalendarEvent).and_call_original
          allow(migration).to receive(:imported_migration_items_by_class).with(AssignmentOverride).and_call_original
          allow(migration).to receive(:imported_migration_items_by_class).with(ContextModule).and_call_original
          allow(migration).to receive(:imported_migration_items_by_class).with(WikiPage).and_call_original
          allow(migration).to receive(:imported_migration_items_by_class).with(Attachment).and_call_original
          allow(migration).to receive(:imported_migration_items_by_class).with(Folder).and_call_original
          allow(migration).to receive(:imported_migration_items_by_class).with(Announcement).and_call_original
          allow(migration).to receive(:imported_migration_items_by_class).with(DiscussionTopic).and_call_original
          allow(migration).to receive(:imported_migration_items_by_class).with(Assignment).and_call_original
          allow(migration).to receive(:imported_migration_items_by_class).with(Quizzes::Quiz).and_call_original
        end

        it "should adjust Assignment dates" do
          expect(migration).to receive(:imported_migration_items_by_class).with(Assignment).and_call_original
          subject
        end

        it "should adjust Quiz::Quizzes dates" do
          expect(migration).to receive(:imported_migration_items_by_class).with(Quizzes::Quiz).and_call_original
          subject
        end
      end
    end
  end

  describe "shift_date_options_from_migration" do
    let(:course) { course_model }
    let(:migration) do
      course.content_migrations.create!(
        migration_settings: {
          date_shift_options: {}
        },
        source_course: Course.create!
      )
    end

    before do
      allow(course).to receive_messages(real_start_date: Date.parse("2023-01-01"), real_end_date: Date.parse("2023-12-31"))
      allow(Importers::CourseContentImporter).to receive(:shift_date_options).and_call_original
    end

    describe "fill_missing_dates_from_source_course FF" do
      context "when the feature flag is disabled" do
        it "doesn't call shift_date_options with source_course if dates were not filled from course" do
          allow(migration.course).to receive_messages(real_start_date: nil, real_end_date: nil)
          Importers::CourseContentImporter.shift_date_options_from_migration(migration)
          expect(Importers::CourseContentImporter).not_to have_received(:shift_date_options)
            .with(migration.source_course, migration.date_shift_options)
        end
      end

      context "when the feature flag is enabled" do
        before do
          Account.site_admin.enable_feature!(:fill_missing_dates_from_source_course)
          allow(migration.source_course).to receive_messages(real_start_date: Date.parse("2024-01-01"), real_end_date: Date.parse("2024-12-31"))
        end

        it "doesn't call shift_date_options with source_course if dates were filled from course" do
          Importers::CourseContentImporter.shift_date_options_from_migration(migration)
          expect(Importers::CourseContentImporter).not_to have_received(:shift_date_options)
            .with(migration.source_course, migration.date_shift_options)
        end

        it "call shift_date_options with source_course if dates were not filled from course" do
          allow(course).to receive_messages(real_start_date: nil, real_end_date: nil)
          Importers::CourseContentImporter.shift_date_options_from_migration(migration)
          expect(Importers::CourseContentImporter).to have_received(:shift_date_options)
            .with(migration.source_course, migration.date_shift_options)
            .exactly(:once)
        end
      end
    end
  end

  describe "import_media_objects" do
    before do
      @kmh = double(KalturaMediaFileHandler)
      allow(KalturaMediaFileHandler).to receive(:new).and_return(@kmh)
      MediaObject.create!(media_id: "maybe")
      attachment_model(uploaded_data: stub_file_data("test.m4v", "asdf", "video/mp4"), media_entry_id: "maybe")
    end

    it "waits for media objects on canvas cartridge import" do
      migration = double(canvas_import?: true)
      expect(@kmh).to receive(:add_media_files).with([@attachment], true)
      Importers::CourseContentImporter.import_media_objects([@attachment], migration)
    end

    it "does not wait for media objects on other import" do
      migration = double(canvas_import?: false)
      expect(@kmh).to receive(:add_media_files).with([@attachment], false)
      Importers::CourseContentImporter.import_media_objects([@attachment], migration)
    end
  end

  describe "import_settings_from_migration" do
    shared_examples "setting set correctly" do |param|
      it "should set #{param} when data exist" do
        data = { course: { param => true } }
        Importers::CourseContentImporter.import_settings_from_migration(@course, data, @cm)
        expect(@course.settings[param]).to be_truthy
      end

      it "should not set #{param} when data not exist" do
        data = { course: {} }
        Importers::CourseContentImporter.import_settings_from_migration(@course, data, @cm)
        expect(@course.settings).not_to have_key(param)
      end
    end

    before :once do
      course_with_teacher
      @course.storage_quota = 1
      @cm = ContentMigration.create!(
        context: @course,
        user: @user,
        source_course: @course,
        copy_options: { everything: "1" }
      )
    end

    context "with unauthorized user" do
      it "does not adjust in course import" do
        Importers::CourseContentImporter.import_settings_from_migration(@course, { course: { storage_quota: 4 } }, @cm)
        expect(@course.storage_quota).to eq 1
      end

      it "does not adjust in course copy" do
        @cm.migration_type = "course_copy_importer"
        Importers::CourseContentImporter.import_settings_from_migration(@course, { course: { storage_quota: 4 } }, @cm)
        expect(@course.storage_quota).to eq 1
      end
    end

    context "with account admin" do
      before :once do
        account_admin_user(user: @user)
      end

      it "adjusts in course import" do
        Importers::CourseContentImporter.import_settings_from_migration(@course, { course: { storage_quota: 4 } }, @cm)
        expect(@course.storage_quota).to eq 4
      end

      it "adjusts in course copy" do
        @cm.migration_type = "course_copy_importer"
        Importers::CourseContentImporter.import_settings_from_migration(@course, { course: { storage_quota: 4 } }, @cm)
        expect(@course.storage_quota).to eq 4
      end
    end

    context "with allow_student_discussion_reporting" do
      include_examples "setting set correctly", :allow_student_discussion_reporting
    end

    context "with allow_student_anonymous_discussion_topics" do
      include_examples "setting set correctly", :allow_student_anonymous_discussion_topics
    end
  end

  describe "audit logging" do
    subject { Importers::CourseContentImporter.import_content(course, data, params, migration) }

    let(:course) { course_factory }
    let(:data) do
      json = File.read(File.join(IMPORT_JSON_DIR, "assessments.json"))
      JSON.parse(json).with_indifferent_access
    end
    let(:params) { { "copy" => { "quizzes" => { "i7ed12d5eade40d9ee8ecb5300b8e02b2" => true } } } }
    let(:migration) do
      migration = ContentMigration.create!(context: course)
      migration.migration_settings[:migration_ids_to_import] = params
      migration.source_course = course
      migration.initiated_source = :manual
      migration.user = @user
      migration.started_at = Time.zone.now
      migration.save!
      migration
    end

    it "logs content migration in audit logs" do
      expect(Auditors::Course).to receive(:record_copied).once.with(migration.source_course, course, migration.user, source: migration.initiated_source)
      expect(Lti::PlatformNotificationService).to receive(:notify_tools_in_course).once.with(course, anything)
      expect(Lti::Pns::LtiContextCopyNoticeBuilder).to receive(:new).once.with(course:, copied_at: migration.started_at.iso8601, source_course: migration.source_course)

      subject
    end

    context "with lti_context_copy_notice flag disabled" do
      before do
        course.root_account.disable_feature!(:lti_context_copy_notice)
      end

      it "does not send LTI Platform Notice" do
        expect(Lti::PlatformNotificationService).not_to receive(:notify_tools_in_course)

        subject
      end
    end
  end

  describe "insert into module" do
    before :once do
      course_factory
      @module = @course.context_modules.create! name: "test"
      @module.add_item(type: "context_module_sub_header", title: "blah")
      @params = { "copy" => { "assignments" => { "1865116198002" => true } } }
      json = File.read(File.join(IMPORT_JSON_DIR, "import_from_migration.json"))
      @data = JSON.parse(json).with_indifferent_access
    end

    it "appends imported items to a module" do
      migration = @course.content_migrations.build
      migration.migration_settings[:migration_ids_to_import] = @params
      migration.migration_settings[:insert_into_module_id] = @module.id
      migration.save!

      Importers::CourseContentImporter.import_content(@course, @data, @params, migration)
      expect(@module.content_tags.order("position").pluck(:content_type)).to eq(%w[ContextModuleSubHeader Assignment])
    end

    it "can insert items from one module to an existing module" do
      migration = @course.content_migrations.build
      @params["copy"]["context_modules"] = { "1864019962002" => true }
      migration.migration_settings[:migration_ids_to_import] = @params
      migration.migration_settings[:insert_into_module_id] = @module.id
      migration.save!

      Importers::CourseContentImporter.import_content(@course, @data, @params, migration)
      expect(migration.migration_issues.count).to eq 0
      expect(@course.context_modules.where.not(migration_id: nil).count).to eq 0 # doesn't import other modules
      expect(@module.content_tags.last.content.migration_id).to eq "1865116198002"
    end

    it "inserts imported items into a module" do
      migration = @course.content_migrations.build
      migration.migration_settings[:migration_ids_to_import] = @params
      migration.migration_settings[:insert_into_module_id] = @module.id
      migration.migration_settings[:insert_into_module_position] = 1
      migration.save!

      Importers::CourseContentImporter.import_content(@course, @data, @params, migration)
      expect(@module.content_tags.order("position").pluck(:content_type)).to eq(%w[Assignment ContextModuleSubHeader])
    end

    it "respects insert_into_module_type" do
      @params["copy"]["discussion_topics"] = { "1864019689002" => true }
      migration = @course.content_migrations.build
      migration.migration_settings[:migration_ids_to_import] = @params
      migration.migration_settings[:insert_into_module_id] = @module.id
      migration.migration_settings[:insert_into_module_type] = "assignment"
      migration.save!
      Importers::CourseContentImporter.import_content(@course, @data, @params, migration)
      expect(@module.content_tags.order("position").pluck(:content_type)).to eq(%w[ContextModuleSubHeader Assignment])
    end
  end

  describe "move to assignment group" do
    before :once do
      course_factory
      @course.require_assignment_group
      @new_group = @course.assignment_groups.create!(name: "new group")
      @params = { copy: {
        assignments: { "1865116014002" => true },
        quizzes: { "1865116160002" => true }
      } }.with_indifferent_access
      json = File.read(File.join(IMPORT_JSON_DIR, "import_from_migration.json"))
      @data = JSON.parse(json).with_indifferent_access
      @migration = @course.content_migrations.build
      @migration.migration_settings[:migration_ids_to_import] = @params
      @migration.migration_settings[:move_to_assignment_group_id] = @new_group.id
      @migration.save!
    end

    it "puts a new assignment into assignment group" do
      @course.assignments.create! title: "other", assignment_group: @new_group
      Importers::CourseContentImporter.import_content(@course, @data, @params, @migration)
      new_assign = @course.assignments.find_by(migration_id: "1865116014002")
      expect(new_assign.assignment_group_id).to eq @new_group.id
    end

    it "moves existing assignment into assignment group" do
      existing_assign = @course.assignments.create! title: "blah", migration_id: "1865116014002"
      expect(existing_assign.assignment_group_id).not_to eq @new_group.id
      Importers::CourseContentImporter.import_content(@course, @data, @params, @migration)
      expect(existing_assign.reload.assignment_group_id).to eq @new_group.id
    end

    it "moves classic quiz assignment into new group" do
      Importers::CourseContentImporter.import_content(@course, @data, @params, @migration)
      quiz = @course.quizzes.find_by(migration_id: "1865116160002")
      expect(quiz.reload.assignment_group_id).to eq @new_group.id
      expect(quiz.assignment.reload.assignment_group_id).to eq @new_group.id
    end
  end

  it "is able to i18n without keys" do
    expect { Importers::CourseContentImporter.translate("stuff") }.not_to raise_error
  end

  it "does not create missing link migration issues if the link got sanitized away" do
    data = { assignments: [
      { migration_id: "broken", description: "heres a normal bad link <a href='/badness'>blah</a>" },
      { migration_id: "kindabroken", description: "here's a link that's going to go away in a bit <link rel=\"stylesheet\" href=\"/badness\"/>" }
    ] }.with_indifferent_access

    course_factory
    migration = @course.content_migrations.create!
    Importers::CourseContentImporter.import_content(@course, data, {}, migration)

    broken_assmt = @course.assignments.where(migration_id: "broken").first
    unbroken_assmt = @course.assignments.where(migration_id: "kindabroken").first
    expect(unbroken_assmt.description).to_not include("stylesheet")

    expect(migration.migration_issues.count).to eq 1 # should ignore the sanitized one
    expect(migration.migration_issues.first.fix_issue_html_url).to eq "/courses/#{@course.id}/assignments/#{broken_assmt.id}"
  end

  describe "metrics logging" do
    subject { Importers::CourseContentImporter.import_content(@course, {}, {}, migration) }

    before do
      allow(InstStatsd::Statsd).to receive(:distributed_increment)
      allow(InstStatsd::Statsd).to receive(:timing)
    end

    before :once do
      course_factory
    end

    let(:migration) { @course.content_migrations.create! migration_type: "atypeofmigration" }

    it "logs import successes" do
      subject
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with("content_migrations.import_success").once
    end

    it "logs import duration" do
      subject
      expect(InstStatsd::Statsd).to have_received(:timing).with("content_migrations.import_duration", anything, {
                                                                  tags: { migration_type: "atypeofmigration" }
                                                                }).once
    end

    it "logs import failures" do
      allow(Auditors::Course).to receive(:record_copied).and_raise("Something went wrong at the last minute")
      expect { subject }.to raise_error("Something went wrong at the last minute")
      expect(InstStatsd::Statsd).to have_received(:distributed_increment).with("content_migrations.import_failure").once
    end

    it "Does not log duration on failures" do
      allow(Auditors::Course).to receive(:record_copied).and_raise("Something went wrong at the last minute")
      expect { subject }.to raise_error("Something went wrong at the last minute")
      expect(InstStatsd::Statsd).to_not have_received(:timing).with("content_migrations.import_failure")
    end
  end

  describe "#error_on_dates?" do
    let(:item) { double("item") }
    let(:attributes) { [:due_at] }

    context "when there are errors on the given attributes" do
      before do
        allow(item).to receive(:errors).and_return({ due_at: ["validation error"] })
      end

      it "returns true" do
        expect(Importers::CourseContentImporter.error_on_dates?(item, attributes)).to be true
      end
    end

    context "when there are no errors on the given attributes" do
      before do
        allow(item).to receive(:errors).and_return({ due_at: [] })
      end

      it "returns false" do
        expect(Importers::CourseContentImporter.error_on_dates?(item, attributes)).to be false
      end
    end

    context "when attributes is empty" do
      let(:attributes) { [] }

      it "returns false" do
        expect(Importers::CourseContentImporter.error_on_dates?(item, attributes)).to be false
      end
    end

    context "when item errors is empty" do
      before do
        allow(item).to receive(:errors).and_return({})
      end

      it "returns false" do
        expect(Importers::CourseContentImporter.error_on_dates?(item, attributes)).to be false
      end
    end
  end

  describe "any_shift_date_missing?" do
    it "returns false when all dates are present" do
      options = {
        old_start_date: "2023-01-01",
        old_end_date: "2023-12-31",
        new_start_date: "2024-01-01",
        new_end_date: "2024-12-31"
      }
      expect(Importers::CourseContentImporter.any_shift_date_missing?(options)).to be false
    end

    it "returns true when old_start_date is missing" do
      options = {
        old_end_date: "2023-12-31",
        new_start_date: "2024-01-01",
        new_end_date: "2024-12-31"
      }
      expect(Importers::CourseContentImporter.any_shift_date_missing?(options)).to be true
    end

    it "returns true when old_end_date is missing" do
      options = {
        old_start_date: "2023-01-01",
        new_start_date: "2024-01-01",
        new_end_date: "2024-12-31"
      }
      expect(Importers::CourseContentImporter.any_shift_date_missing?(options)).to be true
    end

    it "returns true when new_start_date is missing" do
      options = {
        old_start_date: "2023-01-01",
        old_end_date: "2023-12-31",
        new_end_date: "2024-12-31"
      }
      expect(Importers::CourseContentImporter.any_shift_date_missing?(options)).to be true
    end

    it "returns true when new_end_date is missing" do
      options = {
        old_start_date: "2023-01-01",
        old_end_date: "2023-12-31",
        new_start_date: "2024-01-01"
      }
      expect(Importers::CourseContentImporter.any_shift_date_missing?(options)).to be true
    end
  end
end

def from_file_path(path, course)
  list = path.split("/").reject(&:empty?)
  filename = list.pop
  folder = Folder.assert_path(list.join("/"), course)
  file = folder.file_attachments.build(display_name: filename, filename:, content_type: "text/plain")
  file.uploaded_data = StringIO.new("fake data")
  file.context = course
  file.save!
  file
end
