# frozen_string_literal: true

#
# Copyright (C) 2017 - present Instructure, Inc.
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

require_relative "../helpers/blueprint_common"

describe "blueprint courses discussions" do
  include_context "in-process server selenium tests"
  include BlueprintCourseCommon

  context "checkpointed discussion" do
    it "creates submissions in for associated assignment and sub-assignments" do
      @master = course_factory(active_all: true)
      @master_teacher = teacher_in_course(course: @master, active_all: true).user
      @template = MasterCourses::MasterTemplate.set_as_master_course(@master)
      @minion = @template.add_child_course!(course_factory(name: "Minion", active_all: true)).child_course
      @minion.enroll_teacher(@master_teacher).accept!
      student_in_course(course: @minion, active_all: true)

      @original_disc = DiscussionTopic.create_graded_topic!(course: @master, title: "From Original Checkpointed Discussion")
      Checkpoints::DiscussionCheckpointCreatorService.call(
        discussion_topic: @original_disc,
        checkpoint_label: CheckpointLabels::REPLY_TO_TOPIC,
        dates: [{ type: "everyone", due_at: 2.days.from_now }],
        points_possible: 5
      )

      Checkpoints::DiscussionCheckpointCreatorService.call(
        discussion_topic: @original_disc,
        checkpoint_label: CheckpointLabels::REPLY_TO_ENTRY,
        dates: [{ type: "everyone", due_at: 5.days.from_now }],
        points_possible: 15,
        replies_required: 3
      )
      run_master_course_migration(@master)
      @copy_disc = @minion.discussion_topics.last
      expect(@copy_disc.assignment.submissions.where(user_id: @student.id).length).to eq 1
      expect(@copy_disc.assignment.sub_assignment_submissions.where(user_id: @student.id).length).to eq 2

      # at this point, we are good, we just need to make sure speedgrader loads the student's submission
      user_session(@master_teacher)
      get "/courses/#{@minion.id}/gradebook/speed_grader?assignment_id=#{@copy_disc.assignment.id}"
      expect(f("#speed_grader_checkpoints_mount_point")).to be_present
    end
  end

  context "regular discussion" do
    before :once do
      @master = course_factory(active_all: true)
      @master_teacher = @teacher
      @template = MasterCourses::MasterTemplate.set_as_master_course(@master)
      @minion = @template.add_child_course!(course_factory(name: "Minion", active_all: true)).child_course
      @minion.enroll_teacher(@master_teacher).accept!

      # sets up the discussion that gets blueprinted
      @original_disc = @master.discussion_topics.create!(title: "Discussion time!")
      run_master_course_migration(@master)
      @copy_disc = @minion.discussion_topics.last
    end

    describe "as a blueprint's teacher" do
      before do
        user_session(@master_teacher)
      end

      it "locks down the associated course's discussion fields", priority: 2 do
        skip "Will be fixed in VICE-5431"
        change_blueprint_settings(@master, points: true, due_dates: true, availability_dates: true)
        get "/courses/#{@master.id}/discussion_topics/#{@original_disc.id}"
        f(".bpc-lock-toggle button").click
        expect(f(".bpc-lock-toggle__label")).to include_text("Locked")
        run_master_course_migration(@master)
        get "/courses/#{@minion.id}/discussion_topics/#{@copy_disc.id}/edit"
        expect(f("#discussion-details-tab")).to contain_css(".tox-tinymce .tox-editor-container")
        expect(f(".bpc-lock-toggle__label")).to include_text("Locked")
        expect(f("#delayed_post_at")).to have_attribute("readonly", "true")
        expect(f("#lock_at")).to have_attribute("readonly", "true")
      end
    end
  end
end
