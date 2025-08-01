/*
 * Copyright (C) 2021 - present Instructure, Inc.
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

import {
  getSpeedGraderUrl,
  updateDiscussionTopicEntryCounts,
  responsiveQuerySizes,
  isTopicAuthor,
  getDisplayName,
  getOptimisticResponse,
  buildQuotedReply,
  addReplyToAllRootEntries,
  addSubentriesCountToParentEntry,
} from '../../utils'
import {AlertManagerContext} from '@canvas/alerts/react/AlertManager'
import {
  DELETE_DISCUSSION_ENTRY,
  UPDATE_DISCUSSION_ENTRY_PARTICIPANT,
  UPDATE_DISCUSSION_ENTRY,
} from '../../../graphql/Mutations'
import DateHelper from '@canvas/datetime/dateHelper'
import {Discussion} from '../../../graphql/Discussion'
import {DiscussionEntry} from '../../../graphql/DiscussionEntry'
import {DISCUSSION_ENTRY_ALL_ROOT_ENTRIES_QUERY} from '../../../graphql/Queries'
import {DiscussionEdit} from '../../components/DiscussionEdit/DiscussionEdit'
import {Flex} from '@instructure/ui-flex'
import {Highlight} from '../../components/Highlight/Highlight'
import {useScope as createI18nScope} from '@canvas/i18n'
import {Spinner} from '@instructure/ui-spinner'
import {
  SearchContext,
  DiscussionManagerUtilityContext,
  AllThreadsState,
} from '../../utils/constants'
import {DiscussionEntryContainer} from '../DiscussionEntryContainer/DiscussionEntryContainer'
import PropTypes from 'prop-types'
import React, {useContext, useEffect, useState, useCallback, useRef, useMemo} from 'react'
import * as ReactDOMServer from 'react-dom/server'
import {ReplyInfo} from '../../components/ReplyInfo/ReplyInfo'
import {Responsive} from '@instructure/ui-responsive'

import theme from '@instructure/canvas-theme'
import {ThreadActions} from '../../components/ThreadActions/ThreadActions'
import {ThreadingToolbar} from '../../components/ThreadingToolbar/ThreadingToolbar'
import {useMutation, useQuery} from '@apollo/client'
import {View} from '@instructure/ui-view'
import {ReportReply} from '../../components/ReportReply/ReportReply'
import {Text} from '@instructure/ui-text'
import useCreateDiscussionEntry from '../../hooks/useCreateDiscussionEntry'
import {useUpdateDiscussionThread} from '../../hooks/useUpdateDiscussionThread'
import {useEventHandler, KeyboardShortcuts} from '../../KeyboardShortcuts/useKeyboardShortcut'
import useHighlightStore from '../../hooks/useHighlightStore'
import useSpeedGrader from '../../hooks/useSpeedGrader'

const I18n = createI18nScope('discussion_topics_post')

const defaultExpandedReplies = id => {
  if (
    (ENV.DISCUSSION?.preferences?.discussions_splitscreen_view &&
      !window.top.location.href.includes('speed_grader')) ||
    id === ENV.discussions_deep_link?.entry_id
  )
    return false
  if (id === ENV.discussions_deep_link?.root_entry_id) return true

  return false
}

export const DiscussionThreadContainer = props => {
  const replyButtonRef = useRef()
  const expansionButtonRef = useRef()
  const moreOptionsButtonRef = useRef()

  const {isInSpeedGrader, handleCommentKeyPress, handleGradeKeyPress} = useSpeedGrader()

  const {searchTerm, filter, allThreadsStatus, expandedThreads, setExpandedThreads} =
    useContext(SearchContext)
  const {setOnFailure, setOnSuccess} = useContext(AlertManagerContext)
  const {replyFromId, setReplyFromId, usedThreadingToolbarChildRef} = useContext(
    DiscussionManagerUtilityContext,
  )
  const [expandReplies, setExpandReplies] = useState(
    defaultExpandedReplies(props.discussionEntry._id),
  )
  const [isEditing, setIsEditing] = useState(false)
  const [editorExpanded, setEditorExpanded] = useState(false)
  const [threadRefCurrent, setThreadRefCurrent] = useState(null)
  const [showReportModal, setShowReportModal] = useState(false)
  const [reportModalIsLoading, setReportModalIsLoading] = useState(false)
  const [reportingError, setReportingError] = useState(false)
  const [firstSubReply, setFirstSubReply] = useState(false)
  const {
    updateLoadedSubentry,
    updateDiscussionEntryParticipant,
    updateDiscussionThreadReadState,
    toggleUnread,
  } = useUpdateDiscussionThread({
    discussionEntry: props.discussionEntry,
    discussionTopic: props.discussionTopic,
    setLoadedSubentries: props.setLoadedSubentries,
  })

  const updateCache = (cache, result) => {
    const newDiscussionEntry = result.data.createDiscussionEntry.discussionEntry
    updateDiscussionTopicEntryCounts(cache, props.discussionTopic.id, {repliesCountChange: 1})
    addReplyToAllRootEntries(cache, newDiscussionEntry)
    addSubentriesCountToParentEntry(cache, newDiscussionEntry)
    props.setHighlightEntryId(newDiscussionEntry._id)
  }

  const onEntryCreationCompletion = (data, success) => {
    if (success) {
      // It is a known issue that the first reply of a sub reply has not initiated the sub query call,
      // as a result we cannot add an entry to it. Before we had expand buttons for each sub-entry,
      // now we must manually trigger the first one.
      // See addReplyToDiscussionEntry definition for more details.
      if (
        data.createDiscussionEntry.discussionEntry.parentId === props.discussionEntry._id &&
        !props.discussionEntry.subentriesCount
      ) {
        setFirstSubReply(true)
      }
      setExpandReplies(true)
      props.setHighlightEntryId(data.createDiscussionEntry.discussionEntry._id)
      setEditorExpanded(false)
    }
  }

  const removeRef = useHighlightStore(state => state.removeReplyRef)

  useEffect(() => {
    if (props.discussionEntry._id === props.highlightEntryId) {
      window.top.postMessage({
        subject: 'SG.handleHighlightedEntryChange',
        entryTimestamp: props.discussionEntry.createdAt,
      })
    }
  }, [props.highlightEntryId])

  useEffect(() => {
    return () => {
      removeRef(props.discussionEntry._id)
    }
  }, [removeRef, props.discussionEntry._id])

  const {createDiscussionEntry, isSubmitting} = useCreateDiscussionEntry(
    onEntryCreationCompletion,
    updateCache,
  )

  const [deleteDiscussionEntry] = useMutation(DELETE_DISCUSSION_ENTRY, {
    onCompleted: data => {
      if (!data.deleteDiscussionEntry.errors) {
        updateLoadedSubentry(data.deleteDiscussionEntry.discussionEntry)
        setOnSuccess(I18n.t('The reply was successfully deleted.'))
      } else {
        setOnFailure(I18n.t('There was an unexpected error while deleting the reply.'))
      }
    },
    onError: () => {
      setOnFailure(I18n.t('There was an unexpected error while deleting the reply.'))
    },
    update: () => {
      if (props.refetchDiscussionEntries) props.refetchDiscussionEntries()
    },
  })

  const [updateDiscussionEntry] = useMutation(UPDATE_DISCUSSION_ENTRY, {
    onCompleted: data => {
      if (!data.updateDiscussionEntry.errors) {
        updateLoadedSubentry(data.updateDiscussionEntry.discussionEntry)
        setOnSuccess(I18n.t('The reply was successfully updated.'))
        setIsEditing(false)
      } else {
        setOnFailure(I18n.t('There was an unexpected error while updating the reply.'))
      }
    },
    onError: () => {
      setOnFailure(I18n.t('There was an unexpected error while updating the reply.'))
    },
  })

  const [updateDiscussionEntryReported] = useMutation(UPDATE_DISCUSSION_ENTRY_PARTICIPANT, {
    onCompleted: data => {
      if (!data || !data.updateDiscussionEntryParticipant) {
        return null
      }
      updateLoadedSubentry(data.updateDiscussionEntryParticipant.discussionEntry)
      setReportModalIsLoading(false)
      setShowReportModal(false)
      setOnSuccess(I18n.t('You have reported this reply.'), false)
    },
    onError: () => {
      setReportModalIsLoading(false)
      setReportingError(true)
      setTimeout(() => {
        setReportingError(false)
      }, 3000)
    },
  })

  const toggleRatingKeyboard = e => {
    if (e.detail.entryId === props.discussionEntry._id && props.discussionEntry.permissions.rate) {
      toggleRating()
    }
  }

  const toggleRating = () => {
    updateDiscussionEntryParticipant({
      variables: {
        discussionEntryId: props.discussionEntry._id,
        rating: props.discussionEntry.entryParticipant?.rating ? 'not_liked' : 'liked',
      },
    })
  }

  useEventHandler(KeyboardShortcuts.TOGGLE_RATING_KEYBOARD, toggleRatingKeyboard)

  const getReplyLeftMargin = responsiveProp => {
    // In mobile we dont want any margin
    if (responsiveProp.isMobile) {
      return 0
    }
    // If the entry is in threadMode, then we want the RCE to be aligned with the authorInfo
    const threadMode = props.discussionEntry?.depth > 1
    if (responsiveProp.padding === undefined || responsiveProp.padding === null || !threadMode) {
      return `calc(${theme.spacing.xxLarge} * ${props.depth + 1})`
    }
    // This assumes that the responsive prop is using the css short hand for padding with 3 variables to get the left padding value
    const responsiveLeftPadding = responsiveProp.padding.split(' ')[1] || ''
    // The flex component uses the notation xx-small but the canvas theme saves the value as xxSmall
    const camelCaseResponsiveLeftPadding = responsiveLeftPadding.replace(/-(.)/g, (_, nextLetter) =>
      nextLetter.toUpperCase(),
    )
    // Retrieve the css value based on the canvas theme variable
    const discussionEditLeftPadding = theme.spacing[camelCaseResponsiveLeftPadding] || '0'

    // This assumes that the discussionEntryContainer left padding is small
    const discussionEntryContainerLeftPadding = theme.spacing.small || '0'

    return `calc(${theme.spacing.xxLarge} * ${props.depth} + ${discussionEntryContainerLeftPadding} + ${discussionEditLeftPadding})`
  }

  // Condense SplitScreen to one variable & link with the SplitScreenButton
  const splitScreenOn = props.userSplitScreenPreference

  const onShowRepliesKeyboard = e => {
    if (e.detail.entryId === props.discussionEntry._id) {
      onShowReplies()
    }
  }

  const onShowReplies = () => {
    if (splitScreenOn) {
      usedThreadingToolbarChildRef.current = expansionButtonRef.current
      props.onOpenSplitView(props.discussionEntry._id, false)
    } else {
      setExpandReplies(!expandReplies)
    }
  }

  useEventHandler(KeyboardShortcuts.ON_SHOW_REPLIES_KEYBOARD, onShowRepliesKeyboard)

  const showReplies = (
    <ThreadingToolbar.Expansion
      expansionButtonRef={expansionButtonRef}
      key={`expand-${props.discussionEntry._id}`}
      delimiterKey={`expand-delimiter-${props.discussionEntry._id}`}
      authorName={getDisplayName(props.discussionEntry)}
      expandText={
        <ReplyInfo
          replyCount={props.discussionEntry.rootEntryParticipantCounts?.repliesCount}
          unreadCount={props.discussionEntry.rootEntryParticipantCounts?.unreadCount}
          showHide={expandReplies}
        />
      }
      onClick={onShowReplies}
      isExpanded={expandReplies}
    />
  )

  const onThreadReplyKeyboard = e => {
    if (e.detail.entryId === props.discussionEntry._id) {
      onThreadReply()
    }
  }

  const onThreadReply = () => {
    const newEditorExpanded = !editorExpanded
    setEditorExpanded(newEditorExpanded)

    if (splitScreenOn) {
      usedThreadingToolbarChildRef.current = replyButtonRef.current
      props.onOpenSplitView(props.discussionEntry._id, true)
    }
  }

  useEventHandler(KeyboardShortcuts.ON_THREAD_REPLY_KEYBOARD, onThreadReplyKeyboard)

  const getThreadActions = responsiveProp => {
    const threadActions = []

    // On mobile, we display it in another row
    if (!responsiveProp.isMobile && props.depth === 0 && props.discussionEntry.lastReply) {
      threadActions.push(showReplies)
    }

    if (props?.discussionEntry?.permissions?.reply) {
      threadActions.push(
        <ThreadingToolbar.Reply
          replyButtonRef={replyButtonRef}
          key={`reply-${props.discussionEntry._id}`}
          authorName={getDisplayName(props.discussionEntry)}
          delimiterKey={`reply-delimiter-${props.discussionEntry._id}`}
          onClick={onThreadReply}
        />,
      )
    }
    if (
      props.discussionEntry.permissions.viewRating &&
      (props.discussionEntry.permissions.rate || props.discussionEntry.ratingSum > 0)
    ) {
      threadActions.push(
        <ThreadingToolbar.Like
          key={`like-${props.discussionEntry._id}`}
          delimiterKey={`like-delimiter-${props.discussionEntry._id}`}
          onClick={toggleRating}
          authorName={getDisplayName(props.discussionEntry)}
          isLiked={!!props.discussionEntry.entryParticipant?.rating}
          likeCount={props.discussionEntry.ratingSum || 0}
          interaction={props.discussionEntry.permissions.rate ? 'enabled' : 'disabled'}
        />,
      )
    }

    if (ENV.discussion_pin_post) {
      threadActions.push(
        <ThreadingToolbar.Pin
          key={`pin-${props.discussionEntry._id}`}
          delimiterKey={`pin-delimiter-${props.discussionEntry._id}`}
          onClick={() => {}}
        />,
      )
    }

    if (!props.discussionEntry.deleted) {
      threadActions.push(
        <ThreadingToolbar.MarkAsRead
          key={`mark-as-read-${props.discussionEntry._id}`}
          delimiterKey={`mark-as-read-delimiter-${props.discussionEntry._id}`}
          isRead={props.discussionEntry.entryParticipant?.read}
          authorName={getDisplayName(props.discussionEntry)}
          onClick={toggleUnread}
        />,
      )
    }

    return threadActions
  }

  const onDeleteKeyboard = e => {
    if (
      e.detail.entryId === props.discussionEntry._id &&
      props.discussionEntry.permissions.delete
    ) {
      onDelete()
    }
  }

  const onDelete = () => {
    if (window.confirm(I18n.t('Are you sure you want to delete this entry?'))) {
      deleteDiscussionEntry({
        variables: {
          id: props.discussionEntry._id,
        },
      })
    }
  }

  useEventHandler(KeyboardShortcuts.ON_DELETE_KEYBOARD, onDeleteKeyboard)

  const onEditKeyboard = e => {
    if (
      e.detail.entryId === props.discussionEntry._id &&
      props.discussionEntry.permissions.update
    ) {
      onEdit()
    }
  }

  const onEdit = () => {
    setIsEditing(true)
  }

  useEventHandler(KeyboardShortcuts.ON_EDIT_KEYBOARD, onEditKeyboard)

  const onSpeedGraderCommentKeyboard = e => {
    // When full context view is on in speedgrader, the full Discussion view
    // is shown, an entry is also immediately highlighted.
    // because of this highlight, speedgrader's listeners no longer work,
    // so we need to listen for them here instead.
    //
    // NOTE: Splitscreen view is disabled in speedgrader, so we only need to
    // listen here, in threaded view
    //
    // we are checking entry id so that we don't call handleCommentKeyPress for every
    // entry, instead, we call it for just one
    if (isInSpeedGrader && e.detail.entryId === props.discussionEntry._id) {
      handleCommentKeyPress()
    }
  }
  useEventHandler(KeyboardShortcuts.ON_SPEEDGRADER_COMMENT, onSpeedGraderCommentKeyboard)

  const onSpeedGraderGradeKeyboard = e => {
    // When full context view is on in speedgrader, the full Discussion view
    // is shown, an entry is also immediately highlighted.
    // because of this highlight, speedgrader's listeners no longer work,
    // so we need to listen for them here instead.
    //
    // NOTE: Splitscreen view is disabled in speedgrader, so we only need to
    // listen here, in threaded view
    //
    // we are checking entry id so that we don't call handleGradetKeyPress for every
    // entry, instead, we call it for just one
    if (isInSpeedGrader && e.detail.entryId === props.discussionEntry._id) {
      handleGradeKeyPress()
    }
  }
  useEventHandler(KeyboardShortcuts.ON_SPEEDGRADER_GRADE, onSpeedGraderGradeKeyboard)

  const onUpdate = (message, quotedEntryId, file) => {
    updateDiscussionEntry({
      variables: {
        discussionEntryId: props.discussionEntry._id,
        message,
        fileId: file?._id,
        removeAttachment: !file?._id,
        quotedEntryId,
      },
    })
  }

  const onOpenInSpeedGrader = () => {
    window.open(
      getSpeedGraderUrl(props.discussionEntry.author._id, props.discussionEntry._id),
      '_blank',
    )
  }

  // Scrolling auto listener to mark messages as read
  const onThreadRefCurrentSet = useCallback(refCurrent => {
    setThreadRefCurrent(refCurrent)
  }, [])

  const updateReadState = useCallback(
    discussionEntry => {
      props.markAsRead(discussionEntry._id)
      // manually update this entry's read state, then updateLoadedSubentry
      const data = JSON.parse(JSON.stringify(discussionEntry))
      data.entryParticipant.read = !data.entryParticipant?.read
      updateLoadedSubentry(data)
    },
    [props, updateLoadedSubentry],
  )

  useEffect(() => {
    if (
      !ENV.manual_mark_as_read &&
      !props.discussionEntry?.deleted &&
      !props.discussionEntry?.entryParticipant?.read &&
      !props.discussionEntry?.entryParticipant?.forcedReadState
    ) {
      const viewportHeight = window.innerHeight || document.documentElement.clientHeight
      const observer = new IntersectionObserver(
        ([entry]) =>
          (entry.isIntersecting || entry.intersectionRatio > viewportHeight * 0.4) &&
          updateReadState(props.discussionEntry),
        {
          root: null,
          rootMargin: '0px',
          threshold: 0.0,
        },
      )

      if (threadRefCurrent) observer.observe(threadRefCurrent)

      return () => {
        if (threadRefCurrent) observer.unobserve(threadRefCurrent)
      }
    }
  }, [threadRefCurrent, props.discussionEntry.entryParticipant.read, props, updateReadState])

  useEffect(() => {
    if (expandedThreads.includes(props.discussionEntry._id)) {
      setExpandReplies(true)
    }
  }, [expandedThreads, props.discussionEntry._id])

  useEffect(() => {
    if (allThreadsStatus === AllThreadsState.Expanded && !expandReplies) {
      setExpandReplies(true)
    }
    if (allThreadsStatus === AllThreadsState.Collapsed && expandReplies) {
      setExpandReplies(false)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [allThreadsStatus])

  useEffect(() => {
    if (expandReplies && !expandedThreads.includes(props.discussionEntry._id)) {
      setExpandedThreads([...expandedThreads, props.discussionEntry._id])
    } else if (!expandReplies && expandedThreads.includes(props.discussionEntry._id)) {
      setExpandedThreads(expandedThreads.filter(v => v !== props.discussionEntry._id))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expandReplies])

  // This reply is used with inline-view reply
  const onReplySubmit = (message, quotedEntryId, isAnonymousAuthor, file) => {
    const getParentId = () => {
      switch (props.discussionEntry.depth) {
        case 1:
          return props.discussionEntry._id
        case 2:
          return props.discussionEntry._id
        case 3:
          return props.discussionEntry.parentId
        default:
          return props.discussionEntry.rootEntryId
      }
    }
    const variables = {
      discussionTopicId: ENV.discussion_topic_id,
      parentEntryId: getParentId(),
      fileId: file?._id,
      isAnonymousAuthor,
      message,
      quotedEntryId,
    }
    const optimisticResponse = getOptimisticResponse({
      message,
      attachment: file,
      parentId: getParentId(),
      depth: props.discussionEntry.depth,
      rootEntryId: props.discussionEntry.rootEntryId,
      quotedEntry:
        quotedEntryId && typeof buildQuotedReply === 'function'
          ? buildQuotedReply([props.discussionEntry], getParentId())
          : null,
      isAnonymous:
        !!props.discussionTopic.anonymousState && props.discussionTopic.canReplyAnonymously,
    })
    createDiscussionEntry({variables, optimisticResponse})

    props.setHighlightEntryId('DISCUSSION_ENTRY_PLACEHOLDER')
  }

  return (
    <Responsive
      match="media"
      query={responsiveQuerySizes({mobile: true, desktop: true})}
      props={{
        // If you change the padding notation on these, please update the getReplyLeftMargin function
        mobile: {
          marginDepth: `calc(${theme.spacing.medium} * ${props.depth})`,
          padding: '0',
          toolbarLeftPadding: undefined,
          isMobile: true,
        },
        desktop: {
          marginDepth: `calc(${theme.spacing.xxLarge} * ${props.depth})`,
          padding: '0 mediumSmall',
          toolbarLeftPadding: props.depth === 0 ? '0 0 0 xx-small' : undefined,
          isMobile: false,
        },
      }}
      render={responsiveProps => (
        <>
          <Highlight
            isHighlighted={props.discussionEntry._id === props.highlightEntryId}
            discussionEntryId={props.discussionEntry._id}
          >
            <div
              style={{marginLeft: responsiveProps.marginDepth}}
              ref={onThreadRefCurrentSet}
              data-testid="discussion-entry-container"
            >
              <Flex padding={responsiveProps.padding}>
                <Flex.Item shouldShrink={true} shouldGrow={true}>
                  <DiscussionEntryContainer
                    discussionTopic={props.discussionTopic}
                    discussionEntry={props.discussionEntry}
                    toggleUnread={toggleUnread}
                    isTopic={false}
                    postUtilities={
                      !props.discussionEntry.deleted ? (
                        <ThreadActions
                          moreOptionsButtonRef={moreOptionsButtonRef}
                          id={props.discussionEntry._id}
                          authorName={getDisplayName(props.discussionEntry)}
                          isUnread={!props.discussionEntry.entryParticipant?.read}
                          onToggleUnread={toggleUnread}
                          onDelete={props.discussionEntry.permissions?.delete ? onDelete : null}
                          onEdit={props.discussionEntry.permissions?.update ? onEdit : null}
                          onOpenInSpeedGrader={
                            props.discussionTopic.permissions?.speedGrader
                              ? onOpenInSpeedGrader
                              : null
                          }
                          goToParent={
                            props.depth === 0
                              ? null
                              : () => {
                                  props.setHighlightEntryId(props.discussionEntry.parentId)
                                }
                          }
                          goToTopic={props.goToTopic}
                          permalinkId={props.discussionEntry._id}
                          onReport={
                            ENV.discussions_reporting &&
                            props.discussionTopic.permissions?.studentReporting
                              ? () => {
                                  setShowReportModal(true)
                                }
                              : null
                          }
                          isReported={props.discussionEntry?.entryParticipant?.reportType != null}
                          onQuoteReply={
                            props?.discussionEntry?.permissions?.reply
                              ? () => {
                                  setReplyFromId(props.discussionEntry._id)
                                  if (splitScreenOn) {
                                    props.onOpenSplitView(props.discussionEntry._id, true)
                                  } else {
                                    setEditorExpanded(true)
                                  }
                                }
                              : null
                          }
                          onMarkThreadAsRead={
                            props.discussionTopic.discussionType !== 'threaded'
                              ? undefined
                              : readState => {
                                  window.ENV.discussions_deep_link = {
                                    root_entry_id: props.discussionEntry.rootEntryId,
                                    parent_id: props.discussionEntry.parentId,
                                    entry_id: props.discussionEntry._id,
                                  }
                                  updateDiscussionThreadReadState({
                                    variables: {
                                      discussionEntryId: props.discussionEntry.rootEntryId
                                        ? props.discussionEntry.rootEntryId
                                        : props.discussionEntry.id,
                                      read: readState,
                                    },
                                  })
                                  props.setHighlightEntryId(props.discussionEntry._id)
                                }
                          }
                        />
                      ) : null
                    }
                    author={props.discussionEntry.author}
                    anonymousAuthor={props.discussionEntry.anonymousAuthor}
                    message={props.discussionEntry.message}
                    isEditing={isEditing}
                    onSave={onUpdate}
                    onCancel={() => {
                      setIsEditing(false)
                      setTimeout(() => {
                        moreOptionsButtonRef?.current?.focus()
                      }, 0)
                    }}
                    isSplitView={false}
                    editor={props.discussionEntry.editor}
                    isUnread={!props.discussionEntry.entryParticipant?.read}
                    isForcedRead={props.discussionEntry.entryParticipant?.forcedReadState}
                    createdAt={props.discussionEntry.createdAt}
                    timingDisplay={DateHelper.formatDatetimeForDiscussions(
                      props.discussionEntry.createdAt,
                    )}
                    editedTimingDisplay={DateHelper.formatDatetimeForDiscussions(
                      props.discussionEntry.deleted
                        ? props.discussionEntry.updatedAt
                        : props.discussionEntry.editedAt,
                    )}
                    lastReplyAtDisplay={DateHelper.formatDatetimeForDiscussions(
                      props.discussionEntry.lastReply?.createdAt,
                    )}
                    deleted={props.discussionEntry.deleted}
                    isTopicAuthor={isTopicAuthor(
                      props.discussionTopic.author,
                      props.discussionEntry.author,
                    )}
                    attachment={props.discussionEntry.attachment}
                    quotedEntry={props.discussionEntry.quotedEntry}
                  >
                    <View as="div" padding={responsiveProps.toolbarLeftPadding}>
                      <ThreadingToolbar
                        searchTerm={searchTerm}
                        discussionEntry={props.discussionEntry}
                        onOpenSplitView={props.onOpenSplitView}
                        isSplitView={false}
                        filter={filter}
                      >
                        {getThreadActions(responsiveProps)}
                      </ThreadingToolbar>
                    </View>
                    {responsiveProps.isMobile &&
                      props.depth === 0 &&
                      props.discussionEntry.lastReply && (
                        <View as="div" margin="small 0">
                          <ThreadingToolbar
                            searchTerm={searchTerm}
                            discussionEntry={props.discussionEntry}
                            onOpenSplitView={props.onOpenSplitView}
                            isSplitView={false}
                            filter={filter}
                          >
                            {[showReplies]}
                          </ThreadingToolbar>
                        </View>
                      )}
                  </DiscussionEntryContainer>
                  <ReportReply
                    onCloseReportModal={() => {
                      setShowReportModal(false)
                    }}
                    onSubmit={reportType => {
                      updateDiscussionEntryReported({
                        variables: {
                          discussionEntryId: props.discussionEntry._id,
                          reportType,
                        },
                      })
                      setReportModalIsLoading(true)
                    }}
                    showReportModal={showReportModal}
                    isLoading={reportModalIsLoading}
                    errorSubmitting={reportingError}
                  />
                </Flex.Item>
              </Flex>
            </div>
          </Highlight>
          {editorExpanded && !splitScreenOn && (
            <div style={{marginLeft: getReplyLeftMargin(responsiveProps)}}>
              <View
                display="block"
                background="primary"
                padding="none none small none"
                margin="none none x-small none"
              >
                <DiscussionEdit
                  rceIdentifier={props.discussionEntry._id}
                  discussionAnonymousState={props.discussionTopic?.anonymousState}
                  canReplyAnonymously={props.discussionTopic?.canReplyAnonymously}
                  onSubmit={(message, quotedEntryId, file, anonymousAuthorState) => {
                    onReplySubmit(message, quotedEntryId, anonymousAuthorState, file)
                  }}
                  onCancel={() => {
                    setEditorExpanded(false)
                    setTimeout(() => {
                      replyButtonRef?.current?.focus()
                    }, 0)
                  }}
                  isSubmitting={isSubmitting}
                  quotedEntry={buildQuotedReply([props.discussionEntry], replyFromId)}
                  value={
                    !!ENV.rce_mentions_in_discussions && props.discussionEntry.depth > 2
                      ? ReactDOMServer.renderToString(
                          <span
                            className="mceNonEditable mention"
                            data-mention={props.discussionEntry.author?._id}
                          >
                            @{getDisplayName(props.discussionEntry)}
                          </span>,
                        )
                      : ''
                  }
                  isAnnouncement={props.discussionTopic.isAnnouncement}
                />
              </View>
            </div>
          )}
          {((expandReplies && !searchTerm) || props.depth > 0 || firstSubReply) &&
            !splitScreenOn &&
            (props.discussionEntry.subentriesCount > 0 || firstSubReply) && (
              <DiscussionSubentries
                discussionTopic={props.discussionTopic}
                discussionEntryId={props.discussionEntry._id}
                depth={props.depth + 1}
                markAsRead={props.markAsRead}
                parentRefCurrent={threadRefCurrent}
                highlightEntryId={props.highlightEntryId}
                setHighlightEntryId={props.setHighlightEntryId}
                allRootEntries={props.allRootEntries}
              />
            )}
        </>
      )}
    />
  )
}

DiscussionThreadContainer.propTypes = {
  discussionTopic: Discussion.shape,
  discussionEntry: DiscussionEntry.shape,
  refetchDiscussionEntries: PropTypes.func,
  depth: PropTypes.number,
  markAsRead: PropTypes.func,
  onOpenSplitView: PropTypes.func,
  goToTopic: PropTypes.func,
  highlightEntryId: PropTypes.string,
  setHighlightEntryId: PropTypes.func,
  userSplitScreenPreference: PropTypes.bool,
  allRootEntries: PropTypes.array,
  setLoadedSubentries: PropTypes.func,
}

DiscussionThreadContainer.defaultProps = {
  depth: 0,
}

export default DiscussionThreadContainer

const DiscussionSubentries = props => {
  const {setOnFailure} = useContext(AlertManagerContext)
  const [loadedSubentries, setLoadedSubentries] = useState([])

  const variables = {
    discussionEntryID: props.discussionEntryId,
  }

  const query = useQuery(DISCUSSION_ENTRY_ALL_ROOT_ENTRIES_QUERY, {
    variables,
    skip: props.allRootEntries && Array.isArray(props.allRootEntries),
  })

  const pushSubEntries = useHighlightStore(state => state.pushSubEntries)

  useEffect(() => {
    if (query.data) {
      pushSubEntries(
        query.data.legacyNode.allRootEntries.map(({_id, deleted, parentId}) => ({
          _id,
          deleted,
          parentId,
        })),
        props.discussionEntryId,
      )
    }
  }, [query.data, pushSubEntries, props.discussionEntryId])

  const allRootEntries = props.allRootEntries || query?.data?.legacyNode?.allRootEntries || []
  const subentries = allRootEntries.filter(entry => entry.parentId === props.discussionEntryId)
  const subentriesIds = subentries.map(entry => entry._id).join('')

  useEffect(() => {
    const loadedSubentriesIds = loadedSubentries.map(entry => entry._id).join('')

    // this means on all update mutations (including delete) we need to manually update loadedSubentries
    if (subentries.length > 0 && subentriesIds !== loadedSubentriesIds) {
      if (loadedSubentries.length < subentries.length) {
        setTimeout(() => {
          setLoadedSubentries(previousLoadedSubentries => {
            const previousLoadedSubentriesIds = previousLoadedSubentries.map(({_id}) => _id)
            const newLoadedSubentries = subentries
              .slice(loadedSubentries.length, loadedSubentries.length + 10)
              .filter(({_id}) => !previousLoadedSubentriesIds.includes(_id))

            return [...previousLoadedSubentries, ...newLoadedSubentries]
          })
        }, 500)
      } else {
        // There is a mismatch of IDs, so we need to reset the loadedSubentries
        setLoadedSubentries(subentries)
      }
    }
  }, [subentries, loadedSubentries, subentriesIds])

  if (query.error) {
    setOnFailure(I18n.t('There was an unexpected error loading the replies.'))
    return null
  }

  const isLoading = query.loading || loadedSubentries.length < subentries.length

  return (
    <>
      <LoadingReplies isLoading={isLoading} />
      {loadedSubentries.map(entry => (
        <DiscussionSubentriesMemo
          key={`discussion-thread-${entry._id}`}
          depth={props.depth}
          discussionEntry={entry}
          discussionTopic={props.discussionTopic}
          markAsRead={props.markAsRead}
          parentRefCurrent={props.parentRefCurrent}
          highlightEntryId={props.highlightEntryId}
          setHighlightEntryId={props.setHighlightEntryId}
          allRootEntries={allRootEntries}
          setLoadedSubentries={setLoadedSubentries}
        />
      ))}
    </>
  )
}

DiscussionSubentries.propTypes = {
  discussionTopic: Discussion.shape,
  discussionEntryId: PropTypes.string,
  depth: PropTypes.number,
  markAsRead: PropTypes.func,
  parentRefCurrent: PropTypes.object,
  highlightEntryId: PropTypes.string,
  setHighlightEntryId: PropTypes.func,
  allRootEntries: PropTypes.array,
}

const DiscussionSubentriesMemo = props => {
  return useMemo(() => {
    return (
      <DiscussionThreadContainer
        depth={props.depth}
        discussionEntry={props.discussionEntry}
        discussionTopic={props.discussionTopic}
        markAsRead={props.markAsRead}
        parentRefCurrent={props.parentRefCurrent}
        highlightEntryId={props.highlightEntryId}
        setHighlightEntryId={props.setHighlightEntryId}
        allRootEntries={props.allRootEntries}
        setLoadedSubentries={props.setLoadedSubentries}
      />
    )
  }, [
    props.depth,
    props.discussionEntry,
    props.discussionTopic,
    props.markAsRead,
    props.parentRefCurrent,
    props.highlightEntryId,
    props.setHighlightEntryId,
    props.allRootEntries,
    props.setLoadedSubentries,
  ])
}

DiscussionSubentries.propTypes = {
  discussionTopic: Discussion.shape,
  depth: PropTypes.number,
  markAsRead: PropTypes.func,
  parentRefCurrent: PropTypes.object,
  highlightEntryId: PropTypes.string,
  setHighlightEntryId: PropTypes.func,
  allRootEntries: PropTypes.array,
}

const LoadingReplies = props => {
  return useMemo(() => {
    return (
      props.isLoading && (
        <Flex justifyItems="start" margin="0 large" padding="0 x-large">
          <Flex.Item>
            <Spinner renderTitle={I18n.t('Loading more replies')} size="x-small" />
          </Flex.Item>
          <Flex.Item margin="0 0 0 small">
            <Text>{I18n.t('Loading replies...')}</Text>
          </Flex.Item>
        </Flex>
      )
    )
  }, [props.isLoading])
}

LoadingReplies.propTypes = {
  isLoading: PropTypes.bool,
}
