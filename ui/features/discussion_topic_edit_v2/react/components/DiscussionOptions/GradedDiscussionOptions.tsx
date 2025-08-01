/*
 * Copyright (C) 2023 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import React, {useContext} from 'react'

import {View} from '@instructure/ui-view'
import {useScope as createI18nScope} from '@canvas/i18n'
import {AssignmentGroupSelect} from './AssignmentGroupSelect'
import {DisplayGradeAs} from './DisplayGradeAs'
import {PointsPossible} from './PointsPossible'
import {PeerReviewOptions} from './PeerReviewOptions'
import {SyncToSisCheckbox} from './SyncToSisCheckbox'
import {GradingSchemesSelector} from '@canvas/grading-scheme'
import {CheckpointsSettings} from './CheckpointsSettings'
import {Text} from '@instructure/ui-text'
import {ItemAssignToTrayWrapper} from './ItemAssignToTrayWrapper'
import CoursePacingNotice from '@canvas/due-dates/react/CoursePacingNotice'
import MasteryPathToggle from '@canvas/mastery-path-toggle/react/MasteryPathToggle'
import {DiscussionDueDatesContext} from '../../util/constants'
import {AssetProcessorsForDiscussion} from './AssetProcessorsForDiscussion'

type Props = {
  assignmentGroups: [{_id: string; name: string}]
  pointsPossible: number
  setPointsPossible: (points: number | string) => void
  displayGradeAs: string
  setDisplayGradeAs: (id: string | undefined) => void
  assignmentGroup: string
  setAssignmentGroup: (id: string | undefined) => void
  peerReviewAssignment: string
  setPeerReviewAssignment: (id: string | undefined) => void
  peerReviewsPerStudent: number
  setPeerReviewsPerStudent: (peerReviewsPerStudent: number) => void
  peerReviewDueDate: string
  setPeerReviewDueDate: (peerReviewDueDate: string) => void
  postToSis: boolean
  setPostToSis: (postToSis: boolean) => void
  gradingSchemeId?: string
  setGradingSchemeId: (gradingSchemeId: string) => void
  intraGroupPeerReviews: boolean
  setIntraGroupPeerReviews: (intraGroupPeerReviews: boolean) => void
  isCheckpoints: boolean
  canManageAssignTo: boolean
}

const I18n = createI18nScope('discussion_create')

export const GradedDiscussionOptions = ({
  assignmentGroups,
  pointsPossible,
  setPointsPossible,
  displayGradeAs,
  setDisplayGradeAs,
  assignmentGroup,
  setAssignmentGroup,
  peerReviewAssignment,
  setPeerReviewAssignment,
  peerReviewsPerStudent,
  setPeerReviewsPerStudent,
  peerReviewDueDate,
  setPeerReviewDueDate,
  postToSis,
  setPostToSis,
  gradingSchemeId,
  setGradingSchemeId,
  intraGroupPeerReviews,
  setIntraGroupPeerReviews,
  isCheckpoints,
  canManageAssignTo,
}: Props) => {
  const isPacedDiscussion = ENV.IN_PACED_COURSE
  const isPacedWithMasteryPaths =
    ENV.FEATURES.course_pace_pacing_with_mastery_paths && ENV.CONDITIONAL_RELEASE_SERVICE_ENABLED

  const {assignedInfoList, setAssignedInfoList} = useContext(DiscussionDueDatesContext)

  const renderDiffModulesAssignTo = () => {
    if (!canManageAssignTo) {
      return
    }
    return (
      <>
        <Text size="large" as="h2">
          {I18n.t('Assignment Settings')}
        </Text>
        {isPacedDiscussion ? (
          <>
            <CoursePacingNotice courseId={ENV.COURSE_ID} />
            {isPacedWithMasteryPaths && (
              <MasteryPathToggle
                courseId={ENV.COURSE_ID}
                fetchOwnOverrides={false}
                overrides={assignedInfoList}
                useCards={false}
                onSync={setAssignedInfoList}
                itemType="discussionTopic"
                itemContentId={undefined}
              />
            )}
          </>
        ) : (
          <ItemAssignToTrayWrapper />
        )}
      </>
    )
  }

  return (
    <View as="div">
      {!isCheckpoints && (
        <View as="div" margin="medium 0">
          <PointsPossible
            pointsPossible={pointsPossible}
            setPointsPossible={setPointsPossible}
            pointsPossibleLabel={I18n.t('Points Possible')}
            pointsPossibleDataTestId="points-possible-input"
          />
        </View>
      )}
      <View as="div" margin="medium 0">
        <DisplayGradeAs displayGradeAs={displayGradeAs} setDisplayGradeAs={setDisplayGradeAs} />
      </View>
      {(displayGradeAs === 'gpa_scale' || displayGradeAs === 'letter_grade') && (
        <GradingSchemesSelector
          canManage={ENV?.PERMISSIONS?.manage_grading_schemes || false}
          contextId={ENV.COURSE_ID || ''}
          contextType="Course"
          initiallySelectedGradingSchemeId={gradingSchemeId}
          onChange={newSchemeId => setGradingSchemeId(newSchemeId || '')}
          archivedGradingSchemesEnabled={ENV.ARCHIVED_GRADING_SCHEMES_ENABLED ?? false}
          assignmentId={ENV.ASSIGNMENT_ID ? String(ENV.ASSIGNMENT_ID) : undefined}
          courseDefaultSchemeId={ENV.COURSE_DEFAULT_GRADING_SCHEME_ID || ''}
        />
      )}
      {ENV.POST_TO_SIS && (
        <View as="div" margin="medium 0">
          <SyncToSisCheckbox postToSis={postToSis} setPostToSis={setPostToSis} />
        </View>
      )}
      <View as="div" margin="medium 0">
        <AssignmentGroupSelect
          assignmentGroup={assignmentGroup}
          setAssignmentGroup={setAssignmentGroup}
          availableAssignmentGroups={assignmentGroups}
        />
      </View>
      <View as="div" margin="small 0">
        <PeerReviewOptions
          peerReviewAssignment={peerReviewAssignment}
          setPeerReviewAssignment={setPeerReviewAssignment}
          peerReviewsPerStudent={peerReviewsPerStudent || 0}
          setPeerReviewsPerStudent={setPeerReviewsPerStudent}
          peerReviewDueDate={peerReviewDueDate}
          setPeerReviewDueDate={setPeerReviewDueDate}
          intraGroupPeerReviews={intraGroupPeerReviews}
          setIntraGroupPeerReviews={setIntraGroupPeerReviews}
        />
      </View>
      {ENV.FEATURES.lti_asset_processor_discussions && (
        <AssetProcessorsForDiscussion
          courseId={parseInt(ENV.COURSE_ID!)}
          secureParams={'' /* TODO in another commit */}
        />
      )}
      {isCheckpoints && <CheckpointsSettings />}
      <View as="div" margin="medium 0">
        {renderDiffModulesAssignTo()}
      </View>
    </View>
  )
}

GradedDiscussionOptions.defaultProps = {
  pointsPossible: 0,
}
