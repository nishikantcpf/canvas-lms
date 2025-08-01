/*
 * Copyright (C) 2011 - present Instructure, Inc.
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

import $ from 'jquery'
import ModuleDuplicationSpinner from '../react/ModuleDuplicationSpinner'
import React from 'react'
import {createRoot} from 'react-dom/client'
import {reorderElements, renderTray} from '@canvas/move-item-tray'
import LockIconView from '@canvas/lock-icon'
import MasterCourseModuleLock from '../backbone/models/MasterCourseModuleLock'
import {useScope as createI18nScope} from '@canvas/i18n'
import Helper from './context_modules_helper'
import CyoeHelper from '@canvas/conditional-release-cyoe-helper'
import ContextModulesView from '../backbone/views/context_modules' /* handles the publish/unpublish state */
import RelockModulesDialog from '@canvas/relock-modules-dialog'
import vddTooltip from '@canvas/due-dates/jquery/vddTooltip'
import vddTooltipView from '../jst/_vddTooltip.handlebars'
import Publishable from '../backbone/models/Publishable'
import PublishButtonView from '@canvas/publish-button-view'
// eslint-disable-next-line import/no-named-as-default
import htmlEscape from '@instructure/html-escape'
import get from 'lodash/get'
import axios from '@canvas/axios'
import {showFlashError, showFlashAlert} from '@canvas/alerts/react/FlashAlert'
import '@canvas/jquery/jquery.ajaxJSON'
import {dateString, datetimeString} from '@canvas/datetime/date-functions'
import {renderDatetimeField} from '@canvas/datetime/jquery/DatetimeField'
import '@canvas/jquery/jquery.instructure_forms' /* formSubmit, fillFormData, formErrors, errorBox */
import 'jqueryui/dialog'
import '@canvas/util/jquery/fixDialogButtons'
import '@canvas/jquery/jquery.instructure_misc_helpers' /* /\$\.underscore/ */
import '@canvas/jquery/jquery.instructure_misc_plugins' /* .dim, confirmDelete, fragmentChange, showIf */
import '@canvas/jquery/jquery.simulate'
import '@canvas/jquery-keycodes'
import '@canvas/loading-image'
import '@canvas/util/templateData' /* fillTemplateData, getTemplateData */
import '@instructure/date-js' /* Date.parse */
import 'jqueryui/sortable'
import '@canvas/rails-flash-notifications'
import DirectShareCourseTray from '@canvas/direct-sharing/react/components/DirectShareCourseTray'
import DirectShareUserModal from '@canvas/direct-sharing/react/components/DirectShareUserModal'
import ExternalAppsMenuTray from '@canvas/external-apps/react/components/ExternalAppsMenuTray'
import {
  initPublishButton,
  onContainerOverlapped,
  overrideModel,
  prerequisitesMessage,
  refreshDuplicateLinkStatus,
  // eslint-disable-next-line no-redeclare
  scrollTo,
  setExpandAllButton,
  setExpandAllButtonHandler,
  setExpandAllButtonVisible,
  updateProgressionState,
  openExternalTool,
} from './utils'
import ContextModulesPublishMenu from '../react/ContextModulesPublishMenu'
import {renderContextModulesPublishIcon} from '../utils/publishOneModuleHelper'
import {underscoreString} from '@canvas/convert-case'
import {selectContentDialog} from '@canvas/select-content-dialog'
import DifferentiatedModulesTray from '../differentiated-modules'
import ItemAssignToManager from '../differentiated-modules/react/Item/ItemAssignToManager'
import {parseModule, parseModuleList} from '../differentiated-modules/utils/moduleHelpers'
import {addModuleElement, removeEmptyModuleUI, updateModuleFileDrop} from '../utils/moduleHelpers'
import ContextModulesHeader from '../react/ContextModulesHeader'
import doFetchApi from '@canvas/do-fetch-api-effect'
import {ModuleItemsLazyLoader} from '../utils/ModuleItemsLazyLoader'
import {
  moduleFromId,
  hasAllItemsInTheDOM,
  isModuleCollapsed,
  isModulePaginated,
  addShowAllOrLess,
  maybeExpandAndLoadAll,
  expandModuleAndLoadAll,
  loadAll,
  loadFirstPage,
  isModuleCurrentPageEmpty,
  decrementModuleItemsCount,
  MODULE_EXPAND_AND_LOAD_ALL,
  MODULE_LOAD_ALL,
  MODULE_LOAD_FIRST_PAGE,
} from '../utils/showAllOrLess'
import {ModuleItemsStore} from '../utils/ModuleItemsStore'
import {fetchItemTitles} from '../utils/fetchItemTitles'

if (!('INST' in window)) window.INST = {}

const I18n = createI18nScope('context_modulespublic')

// TODO: AMD don't export global, use as module
/* global modules */
window.modules = (function () {
  return {
    updateTaggedItems() {},

    currentIndent($item) {
      const classes = $item.attr('class').split(/\s/)
      let indent = 0
      for (let idx = 0; idx < classes.length; idx++) {
        if (classes[idx].match(/^indent_/)) {
          const new_indent = parseInt(classes[idx].substring(7), 10)
          if (!Number.isNaN(Number(new_indent))) {
            indent = new_indent
          }
        }
      }
      return indent
    },

    addModule(callback = () => {}) {
      const $module = $('#context_module_blank').clone(true).attr('id', 'context_module_new')
      $('#context_modules').append($module)

      const opts = modules.sortable_module_options
      opts.update = modules.updateModuleItemPositions
      $module.find('.context_module_items').sortable(opts)
      $('#context_modules.ui-sortable').sortable('refresh')
      $('#context_modules .context_module .context_module_items.ui-sortable').each(function () {
        $(this).sortable('refresh')
        $(this).sortable('option', 'connectWith', '.context_module_items')
      })
      const options = {initialTab: 'settings'}
      const settings = {
        moduleList: parseModuleList(),
        addModuleUI: (data, $moduleElement) => {
          if (typeof callback === 'function') {
            callback(data, $moduleElement)
          } else {
            addModuleElement(
              data,
              $moduleElement,
              updatePublishMenuDisabledState,
              new RelockModulesDialog(),
              {},
            )
          }
          $moduleElement.css('display', 'block')
        },
      }

      renderDifferentiatedModulesTray(event.target, $module, settings, options)
    },

    updateModulePositions() {
      const ids = []
      $('#context_modules .context_module').each(function () {
        ids.push($(this).attr('id').substring('context_module_'.length))
      })
      const url = `${ENV.CONTEXT_URL_ROOT}/modules/reorder`
      $('#context_modules').loadingImage()
      $.ajaxJSON(
        url,
        'POST',
        {order: ids.join(',')},
        data => {
          $('#context_modules').loadingImage('remove')
          for (const idx in data) {
            const module = data[idx]
            $('#context_module_' + module.context_module.id).triggerHandler('update', module)
          }
        },
        _data => {
          $('#context_modules').loadingImage('remove')
        },
      )
    },

    updateEstimatedDurations(moduleId) {
      if (!ENV.horizon_course) {
        return
      }
      return $.ajaxJSON(
        ENV.CONTEXT_MODULE_ESTIMATED_DURATION_INFO_URL,
        'GET',
        {context_module_id: moduleId},
        data => {
          $(() => {
            $.each(data, (module_id, durations_by_id) => {
              let estimatedDurationSum = 0
              let $context_module_item

              $.each(durations_by_id, (id, info) => {
                $context_module_item = $('#context_module_item_' + id)
                const data = {
                  estimated_duration_minutes: info.estimated_duration_minutes,
                  can_set_estimated_duration: info.can_set_estimated_duration,
                  estimated_duration_display: '',
                }
                if (
                  info.estimated_duration_minutes != null &&
                  info.estimated_duration_minutes > 0
                ) {
                  estimatedDurationSum += info.estimated_duration_minutes
                  $context_module_item.find('.ig-row').removeClass('no-estimated-duration')
                  data.estimated_duration_display = I18n.t('%{minutes} Mins', {
                    minutes: info.estimated_duration_minutes,
                  })
                } else {
                  $context_module_item.find('.ig-row').addClass('no-estimated-duration')
                }
                $context_module_item.fillTemplateData({
                  data,
                  htmlValues: [
                    'estimated_duration_display',
                    'estimated_duration_minutes',
                    'can_set_estimated_duration',
                  ],
                })
              })

              const $moduleHeader = $('#context_module_' + module_id).find('.ig-header')
              const headerData = {
                estimated_duration_header_title: '',
                estimated_duration_header_minutes: '',
              }

              if (estimatedDurationSum > 0) {
                headerData.estimated_duration_header_title = I18n.t('Time to Complete:')
                headerData.estimated_duration_header_minutes = I18n.t('%{minutes} Mins', {
                  minutes: estimatedDurationSum,
                })
              }

              $moduleHeader.fillTemplateData({
                data: headerData,
                htmlValues: [
                  'estimated_duration_header_title',
                  'estimated_duration_header_minutes',
                ],
              })
            })
          })
        },
      )
    },

    async updateModuleItemPositions(_event, ui) {
      const $module = ui.item.parents('.context_module')
      const moduleId = $module.attr('id').substring('context_module_'.length)

      const $originalParentModule = ui.item.data('original-parent')
      const originalParentModuleId = $originalParentModule.data('module-id')

      const url = `${ENV.CONTEXT_URL_ROOT}/modules/${moduleId}/reorder`
      let items = []
      if (ENV.FEATURE_MODULES_PERF && isModulePaginated($module[0])) {
        const pageItemsIds = []
        // the DOM holds just the current page. get their ids
        $module.find('.context_module_items .context_module_item').each(function () {
          pageItemsIds.push($(this).getTemplateData({textValues: ['id']}).id)
        })
        // now get all the module's item ids
        try {
          const allItemsList = await fetchItemTitles(ENV.COURSE_ID, moduleId)
          const allItemsIds = allItemsList.map(item => item.id)
          // find the first index of the pageItemsIds
          const pageItemsIndex = Math.min(
            ...pageItemsIds.map(id => {
              const idx = allItemsIds.indexOf(id)
              return idx === -1 ? Number.MAX_SAFE_INTEGER : idx
            }),
          )

          // replace the slice of allItemsIds with pageItemsIds
          // we know they're contiguous in the array because they're together on the page
          // length-1 becuase we just added an item to the page so there's 1 more id on the page
          // than we want to replace in the allItemsIds array
          allItemsIds.splice(pageItemsIndex, pageItemsIds.length - 1, ...pageItemsIds)
          items = allItemsIds // \o/
        } catch (_e) {
          $module
            .find('.content')
            .errorBox(I18n.t('errors.reorder', 'Reorder failed, please try again.'))
          return
        }
      } else {
        $module.find('.context_module_items .context_module_item').each(function () {
          items.push($(this).getTemplateData({textValues: ['id']}).id)
        })
      }
      $module.find('.context_module_items.ui-sortable').sortable('disable')
      $module.disableWhileLoading(
        $.ajaxJSON(
          url,
          'POST',
          {order: items.join(',')},
          data => {
            if (data && data.context_module && data.context_module.content_tags) {
              for (const idx in data.context_module.content_tags) {
                const tag = data.context_module.content_tags[idx].content_tag
                $module.find('#context_module_item_' + tag.id).fillTemplateData({
                  data: {position: tag.position},
                })
              }
            }
            $module.find('.context_module_items.ui-sortable').sortable('enable')
            updateModuleFileDrop($module[0])

            if (originalParentModuleId != moduleId) {
              if (ENV.FEATURE_MODULES_PERF && originalParentModuleId) {
                decrementModuleItemsCount(originalParentModuleId)
                if (isModuleCurrentPageEmpty($originalParentModule[0])) {
                  loadFirstPage(originalParentModuleId)
                } else {
                  updateModuleFileDrop($originalParentModule[0])
                }
                addShowAllOrLess(moduleId)
              }
            }
          },
          _data => {
            $module.find('.content').loadingImage('remove')
            $module
              .find('.content')
              .errorBox(I18n.t('errors.reorder', 'Reorder failed, please try again.'))
          },
        ),
      )
      $('.context_module .module_header_items').each(function () {
        refreshDuplicateLinkStatus($(this))
      })
    },

    updateProgressions(callback, moduleId) {
      if (!ENV.IS_STUDENT) {
        if (callback) {
          callback()
        }
        return
      }
      const url = $('.progression_list_url').attr('href')
      if ($('.context_module_item.progression_requirement:visible').length > 0) {
        $('.loading_module_progressions_link').show().prop('disabled', true)
      }
      $.ajaxJSON(
        url,
        'GET',
        {context_module_id: moduleId},
        function (data) {
          $('.loading_module_progressions_link').remove()
          const $user_progression_list = $('#current_user_progression_list')
          const progressions = []
          for (const idx in data) {
            progressions.push(data[idx])
          }
          const progressionsFinished = function () {
            if (!$('#context_modules').hasClass('editable')) {
              $('#context_modules .context_module').each(function () {
                updateProgressionState($(this))
              })
            }
            if (callback) {
              callback()
            }
          }
          let progressionCnt = 0
          const nextProgression = function () {
            const data = progressions.shift()
            if (!data) {
              progressionsFinished()
              return
            }
            const progression = data.context_module_progression

            if (progression.user_id == window.ENV.current_user_id) {
              let $user_progression = $user_progression_list.find(
                '.progression_' + progression.context_module_id,
              )

              if ($user_progression.length === 0 && $user_progression_list.length > 0) {
                $user_progression = $user_progression_list.find('.progression_blank').clone(true)
                $user_progression
                  .removeClass('progression_blank')
                  .addClass('progression_' + progression.context_module_id)
                $user_progression_list.append($user_progression)
              }
              if ($user_progression.length > 0) {
                $user_progression.data('requirements_met', progression.requirements_met)
                $user_progression.data(
                  'incomplete_requirements',
                  progression.incomplete_requirements,
                )
                $user_progression.fillTemplateData({data: progression})
              }
            }
            progressionCnt++
            if (progressionCnt >= 50) {
              progressionCnt = 0
              setTimeout(nextProgression, 150)
            } else {
              nextProgression()
            }
          }
          nextProgression()
        },
        () => {
          if (callback) {
            callback()
          }
        },
      )
    },

    updateAssignmentData(callback, moduleId) {
      return $.ajaxJSON(
        ENV.CONTEXT_MODULE_ASSIGNMENT_INFO_URL,
        'GET',
        {context_module_id: moduleId},
        data => {
          $(() => {
            $.each(data, (id, info) => {
              const $context_module_item = $('#context_module_item_' + id)
              const data = {}
              if (info.sub_assignments) {
                updateSubAssignmentData($context_module_item, info.sub_assignments)
              }
              if (info.points_possible != null) {
                data.points_possible_display = I18n.t('points_possible_short', '%{points} pts', {
                  points: I18n.n(info.points_possible),
                })
              }
              if (ENV.IN_PACED_COURSE && !ENV.IS_STUDENT) {
                $context_module_item.find('.due_date_display').remove()
              } else if (info.todo_date != null && info.points_possible == null) {
                data.due_date_display = dateString(info.todo_date)
              } else if (info.due_date != null) {
                if (info.past_due != null) {
                  $context_module_item.data('past_due', true)
                }
                data.due_date_display = dateString(info.due_date)
              } else if (info.has_many_overrides != null) {
                data.due_date_display = I18n.t('Multiple Due Dates')
              } else if (info.vdd_tooltip != null) {
                if (info.vdd_tooltip.due_dates.length === 1) {
                  data.due_date_display = dateString(info.vdd_tooltip.due_dates[0].due_at)
                } else {
                  info.vdd_tooltip.link_href = $context_module_item.find('a.title').attr('href')
                  $context_module_item
                    .find('.due_date_display')
                    .html(vddTooltipView(info.vdd_tooltip))
                }
              } else {
                $context_module_item.find('.due_date_display').remove()
              }
              $context_module_item.fillTemplateData({
                data,
                htmlValues: ['points_possible_display'],
              })

              // clean up empty elements so they don't show borders in updated item group design
              if (info.points_possible === null) {
                $context_module_item.find('.points_possible_display').remove()
              }

              if (info.mc_objectives) {
                $context_module_item.find('.mc_objectives').text(info.mc_objectives)
                $context_module_item.find('.icon-assignment').hide()
                $context_module_item.find('#mc_icon').show()
              } else {
                $context_module_item.find('.mc_objectives').remove()
              }

              $context_module_item.addClass('rendered')
            })

            vddTooltip()
            if (callback) {
              callback()
            }
          })
        },
        () => {
          if (callback) {
            $(callback)
          }
        },
      )
    },

    async loadMasterCourseData(tag_id, moduleId) {
      if (ENV.MASTER_COURSE_SETTINGS) {
        const params = {tag_id, context_module_id: moduleId}
        // Grab the stuff for master courses if needed
        return $.ajaxJSON(
          ENV.MASTER_COURSE_SETTINGS.MASTER_COURSE_DATA_URL,
          'GET',
          params,
          data => {
            if (data.tag_restrictions) {
              Object.entries(data.tag_restrictions).forEach(([id, restriction]) => {
                const item = document.querySelector(
                  `#context_module_item_${id}:not(.master_course_content)`,
                )
                if (item) {
                  item.classList.add('master_course_content')
                  if (Object.keys(restriction).some(r => restriction[r])) {
                    item.setAttribute(
                      'data-master_course_restrictions',
                      JSON.stringify(restriction),
                    )
                  }

                  if (
                    !(
                      ENV.MASTER_COURSE_SETTINGS.IS_CHILD_COURSE &&
                      ENV.HIDE_BLUEPRINT_LOCK_ICON_FOR_CHILDREN
                    )
                  ) {
                    this.initMasterCourseLockButton(item, restriction)
                  }
                }
              })
            }
          },
        )
      }
    },

    itemClass(content_tag) {
      return (
        (content_tag.content_type || '').replace(/^[A-Za-z]+::/, '') + '_' + content_tag.content_id
      )
    },

    updateAllItemInstances(content_tag) {
      $('.context_module_item.' + modules.itemClass(content_tag) + ' .title').each(function () {
        const $this = $(this)
        $this.text(content_tag.title)
        $this.attr('title', content_tag.title)
      })
    },

    addContentTagToEnv(content_tag) {
      ENV.MODULE_FILE_DETAILS[content_tag.id] = {
        content_details: content_tag.content_details,
        content_id: content_tag.content_id,
        id: content_tag.id,
        module_id: content_tag.context_module_id,
      }
    },

    addItemToModule($module, data) {
      if (!data) {
        return $('<div/>')
      }
      data.id = data.id || 'new'
      data.type = data.type || data['item[type]'] || underscoreString(data.content_type)
      data.title = data.title || data['item[title]']
      data.new_tab = data.new_tab ? '1' : '0'
      data.graded = data.graded ? '1' : '0'
      let $item
      const $olditem = data.id !== 'new' ? $('#context_module_item_' + data.id) : []
      if ($olditem.length) {
        const $admin = $olditem.find('.ig-admin')
        if ($admin.length) {
          $admin.detach()
        }
        $item = $olditem.clone(true)
        if ($admin.length) {
          $item.find('.ig-row').append($admin)
        }
      } else {
        $item = $('#context_module_item_blank').clone(true).removeAttr('id')
        modules.evaluateItemCyoe($item, data)
      }
      const speedGraderId = `${data.type}-${data.content_id}`
      const $speedGrader = $item.find('#speed-grader-container-blank')
      $speedGrader.attr('id', 'speed-grader-container-' + speedGraderId)

      const isPublished = data.published
      const isAssignmentOrQuiz =
        data.content_type === 'Assignment' || data.content_type === 'Quizzes::Quiz'
      const isPublishedGradedDiscussion =
        isPublished && data.graded === '1' && data.content_type === 'DiscussionTopic'

      const $speedGraderLinkContainer = $item.find('.speed-grader-link-container')

      if ((isPublished && isAssignmentOrQuiz) || isPublishedGradedDiscussion) {
        $speedGraderLinkContainer.removeClass('hidden')
      }

      $item.addClass(data.type + '_' + data.id)
      $item.addClass(data.quiz_lti ? 'lti-quiz' : data.type)
      if (data.is_duplicate_able) {
        $item.addClass('dupeable')
      }
      $item.attr('aria-label', data.title)
      $item.find('.title').attr('title', data.title)
      $item.fillTemplateData({
        data,
        id: 'context_module_item_' + data.id,
        hrefValues: ['id', 'context_module_id', 'content_id', 'content_type', 'assignment_id'],
      })
      for (let idx = 0; idx < 10; idx++) {
        $item.removeClass('indent_' + idx)
      }
      $item.addClass('indent_' + (data.indent || 0))
      $item.addClass(modules.itemClass(data))

      // This function is called twice, once with the data the user just entered
      // and again after the api request returns. The second time we have
      // all the real data, including the module item's id. Wait until then
      // to add the option.
      if ('id' in data && data.can_manage_assign_to && data.content_type !== 'Attachment') {
        const $assignToMenuItem = $item.find('.assign-to-option')
        if ($assignToMenuItem.length) {
          $assignToMenuItem.removeClass('hidden')
          const $a = $assignToMenuItem.find('a')
          $a.attr('data-item-id', data.id)
          $a.attr('data-item-name', data.title)
          $a.attr(
            'data-item-type',
            data.quiz_lti ? 'lti-quiz' : data.content_type == 'Quizzes::Quiz' ? 'quiz' : data.type,
          )
          $a.attr('data-item-context-id', data.context_id)
          $a.attr('data-item-context-type', data.context_type)
          $a.attr('data-item-content-id', data.content_id)
          $a.attr('data-item-has-assignment', data.assignment_id ? 'true' : 'false')
          $a.attr('data-item-has-assignment-checkpoint', data.is_checkpointed ? 'true' : 'false')
        }
      }

      // don't just tack onto the bottom, put it in its correct position
      let $before = null
      $module
        .find('.context_module_items')
        .children()
        .each(function () {
          const position = parseInt(
            $(this).getTemplateData({textValues: ['position']}).position,
            10,
          )
          if ((data.position || data.position === 0) && (position || position === 0)) {
            if ($before == null && position - data.position >= 0) {
              $before = $(this)
            }
          }
        })
      if ($olditem.length) {
        $olditem.replaceWith($item.show())
      } else if (!$before) {
        $module.find('.context_module_items').append($item.show())
      } else {
        $before.before($item.show())
      }
      if (ENV.FEATURE_MODULES_PERF && $module[0]?.dataset.moduleId) {
        maybeExpandAndLoadAll($module[0].dataset.moduleId, true)
      }
      refreshDuplicateLinkStatus($module)
      return $item
    },

    lazyLoadItems(moduleIds, allPages) {
      const itemsCallback = moduleId => {
        initContextModuleItems(moduleId)
        const uadPromise = modules.updateAssignmentData(
          () => modules.updateProgressions(modules.afterUpdateProgressions, moduleId),
          moduleId,
        )
        let lmcdPromise = Promise.resolve()
        if ($('#context_modules').hasClass('editable')) {
          lmcdPromise = modules.loadMasterCourseData(undefined, moduleId)
        }

        let uedPromise = Promise.resolve()
        if (ENV.horizon_course) {
          uedPromise = modules.updateEstimatedDurations(moduleId)
        }
        addShowAllOrLess(moduleId)
        return Promise.all([uadPromise, lmcdPromise, uedPromise])
      }

      if (moduleIds.length > 0) {
        const moduleItemsLazyLoader = new ModuleItemsLazyLoader(
          ENV.COURSE_ID,
          itemsCallback,
          new ModuleItemsStore(ENV.COURSE_ID, ENV.current_user_id, ENV.ACCOUNT_ID),
        )
        return moduleItemsLazyLoader
          .fetchModuleItems(moduleIds, allPages)
          .then(() => {
            $('#expand_collapse_all').prop('disabled', false)
          })
          .then(() => {
            showFlashAlert({
              message: I18n.t('All module items loaded'),
              type: 'success',
              srOnly: true,
              politness: 'assertive',
            })
          })
      }
    },

    evaluateItemCyoe($item, data) {
      if (!CyoeHelper.isEnabled()) return
      $item = $($item)
      const $itemData = $item.find('.publish-icon')
      const $admin = $item.find('.ig-admin')

      data = data || {
        id: $itemData.attr('data-module-item-id'),
        title: $itemData.attr('data-module-item-name'),
        assignment_id: $itemData.attr('data-assignment-id'),
        is_cyoe_able: $itemData.attr('data-is-cyoeable') === 'true',
      }

      const cyoe = CyoeHelper.getItemData(data.assignment_id, data.is_cyoe_able)

      if (cyoe.isReleased) {
        const fullText = I18n.t('Released by Mastery Path: %{path}', {path: cyoe.releasedLabel})
        const $pathIcon = $(
          '<span class="pill mastery-path-icon" aria-hidden="true" data-tooltip><i class="icon-mastery-paths" /></span>',
        )
          .attr('title', fullText)
          .append(htmlEscape(cyoe.releasedLabel))
        const $srPath = $('<span class="screenreader-only">').append(htmlEscape(fullText))
        $admin.prepend($srPath)
        $admin.prepend($pathIcon)
      }

      if (cyoe.isCyoeAble) {
        const $mpLink = $('<a class="mastery_paths_link" />')
          .attr(
            'href',
            ENV.CONTEXT_URL_ROOT +
              '/modules/items/' +
              data.id +
              '/edit_mastery_paths?return_to=' +
              encodeURIComponent(window.location.pathname),
          )
          .attr('title', I18n.t('Edit Mastery Paths for %{title}', {title: data.title}))
          .text(I18n.t('Mastery Paths'))

        if (cyoe.isTrigger) {
          $admin.prepend($mpLink.clone())
        }

        $admin
          .find('.delete_link')
          .parent()
          .before(
            $('<li role="presentation" />').append(
              $mpLink.prepend('<i class="icon-mastery-path" /> '),
            ),
          )
      }
    },

    getNextPosition($module) {
      let maxPosition = 0
      $module
        .find('.context_module_items')
        .children()
        .each(function () {
          const position = parseInt(
            $(this).getTemplateData({textValues: ['position']}).position,
            10,
          )
          if (position > maxPosition) maxPosition = position
        })
      return maxPosition + 1
    },
    refreshModuleList() {
      $('#module_list').find('.context_module_option').remove()
      $('#context_modules .context_module').each(function () {
        const $this = $(this)
        const data = $this.find('.header').getTemplateData({textValues: ['name']})
        data.id = $this.find('.header').attr('id')
        $this.find('.name').attr('title', data.name)
        const $option = $(document.createElement('option'))
        $option.val(data.id)

        // data.id could come back as undefined, so calling $option.val(data.id) would return an "", which is not chainable, so $option.val(data.id).text... would die.
        $option
          .attr('role', 'option')
          .text(data.name)
          .addClass('context_module_' + data.id)
          .addClass('context_module_option')

        $('#module_list').append($option)
      })
    },
    filterPrerequisites($module, prerequisites) {
      const list = modules.prerequisites()
      const id = $module.attr('id').substring('context_module_'.length)
      const res = []
      for (const idx in prerequisites) {
        if ($.inArray(prerequisites[idx], list[id]) === -1) {
          res.push(prerequisites[idx])
        }
      }
      return res
    },
    prerequisites() {
      const result = {
        to_visit: {},
        visited: {},
      }
      $('#context_modules .context_module').each(function () {
        const id = $(this).attr('id').substring('context_module_'.length)
        result[id] = []
        $(this)
          .find('.prerequisites .criterion')
          .each(function () {
            const pre_id = $(this).getTemplateData({textValues: ['id']}).id
            if ($(this).hasClass('context_module_criterion')) {
              result[id].push(pre_id)
              result.to_visit[id + '_' + pre_id] = true
            }
          })
      })

      for (const val in result.to_visit) {
        if (result.to_visit.hasOwnProperty(val)) {
          const ids = val.split('_')
          if (result.visited[val]) {
            continue
          }
          result.visited[val] = true
          for (const jdx in result[ids[1]]) {
            result[ids[0]].push(result[ids[1]][jdx])
            result.to_visit[ids[0] + '_' + result[ids[1]][jdx]] = true
          }
        }
      }
      delete result.to_visit
      delete result.visited
      return result
    },
    sortable_module_options: {
      connectWith: '.context_module_items',
      handle: '.move_item_link',
      helper: 'clone',
      placeholder: 'context_module_placeholder',
      forcePlaceholderSize: true,
      axis: 'y',
      containment: '#content',
      start: (_event, ui) => {
        // save the original parent module
        ui.item.data('original-parent', ui.item.parents('.context_module'))
      },
    },
    async initMasterCourseLockButton(item, tagRestriction) {
      // add the lock button|icon
      const lockCell = item.querySelector('.lock-icon')
      const data = lockCell ? $($(lockCell)).data() : {}

      const moduleItemId = data.moduleItemId

      const isMasterCourseMasterContent = !!(
        moduleItemId && ENV.MASTER_COURSE_SETTINGS.IS_MASTER_COURSE
      )
      const isMasterCourseChildContent = !!(
        moduleItemId && ENV.MASTER_COURSE_SETTINGS.IS_CHILD_COURSE
      )
      const restricted = !!(
        moduleItemId && Object.keys(tagRestriction).some(r => tagRestriction[r])
      )

      const model = new MasterCourseModuleLock({
        is_master_course_master_content: isMasterCourseMasterContent,
        is_master_course_child_content: isMasterCourseChildContent,
        restricted_by_master_course: restricted,
      })

      const viewOptions = {
        model,
        el: lockCell,
        course_id: ENV.COURSE_ID,
        content_type: data.moduleType,
        content_id: data.contentId,
      }

      const view = new LockIconView(viewOptions)
      view.render()
    },

    afterUpdateProgressions() {
      if (window.location.hash && !window.location.hash.startsWith('#!')) {
        try {
          scrollTo($(window.location.hash))
        } catch (_error) {
          // no-op
        }
      } else {
        const firstContextModuleContent = document
          .querySelector('.context_module')
          ?.querySelector('.content')
        if (!firstContextModuleContent || moduleContentIsHidden(firstContextModuleContent)) {
          const firstVisibleModuleContent = [
            ...document.querySelectorAll('.context_module .content'),
          ].find(el => !moduleContentIsHidden(el))
          if (firstVisibleModuleContent)
            scrollTo($(firstVisibleModuleContent).parents('.context_module'))
        }
      }
    },
  }
})()

const renderDifferentiatedModulesTray = (
  returnFocusTo,
  moduleElement,
  settingsProps,
  options = {initialTab: 'settings'},
) => {
  const container = document.getElementById('differentiated-modules-mount-point')
  if (container.reactRoot) container.reactRoot.unmount()
  container.reactRoot = createRoot(container)
  container.reactRoot.render(
    <DifferentiatedModulesTray
      onDismiss={() => {
        container.reactRoot.unmount()
        returnFocusTo.focus()
      }}
      initialTab={options.initialTab}
      moduleElement={moduleElement}
      courseId={ENV.COURSE_ID ?? ''}
      {...settingsProps}
    />,
  )
}

// Based on the logic from ui/shared/context-modules/differentiated-modules/utils/moduleHelpers.ts
const updateUnlockTime = function ($module, unlock_at) {
  const friendlyDatetime = unlock_at ? datetimeString(unlock_at) : ''

  const unlockAtElement = $module.find('.unlock_at')
  if (unlockAtElement.length) {
    unlockAtElement.text(friendlyDatetime)
  }

  const displayedUnlockAtElement = $module.find('.displayed_unlock_at')
  if (displayedUnlockAtElement.length) {
    displayedUnlockAtElement.text(friendlyDatetime)
    displayedUnlockAtElement.attr('data-html-tooltip-title', friendlyDatetime)
  }

  const unlockDetailsElement = $module.find('.unlock_details')
  if (unlockDetailsElement.length) {
    // User has selected a lock date and that date is in the future
    $module.find('.unlock_details').showIf(unlock_at && Date.parse(unlock_at) > new Date())
  }
}

const updatePrerequisites = function ($module, prereqs) {
  const $prerequisitesDiv = $module.find('.prerequisites')
  let prereqsList = ''
  $prerequisitesDiv.empty()

  if (prereqs.length > 0) {
    for (const i in prereqs) {
      const $div = $('<div />', {
        class: 'prerequisite_criterion ' + prereqs[i].type + '_criterion',
        style: 'float: left;',
      })
      const $spanID = $('<span />', {
        text: htmlEscape(prereqs[i].id),
        class: 'id',
        style: 'display: none;',
      })
      const $spanType = $('<span />', {
        text: htmlEscape(prereqs[i].type),
        class: 'type',
        style: 'display: none;',
      })
      const $spanName = $('<span />', {
        text: htmlEscape(prereqs[i].name),
        class: 'name',
        style: 'display: none;',
      })
      $div.append($spanID)
      $div.append($spanType)
      $div.append($spanName)
      $prerequisitesDiv.append($div)

      prereqsList += prereqs[i].name + ', '
    }
    prereqsList = prereqsList.slice(0, -2)
    const $prerequisitesMessage = $('<div />', {
      text: prerequisitesMessage(prereqsList),
      class: 'prerequisites_message',
    })
    $prerequisitesDiv.append($prerequisitesMessage)
  }
}

// after a module has been updated, update its name as used in other modules' prerequisite lists
const updateOtherPrerequisites = function (id, name) {
  $('div.context_module .prerequisite_criterion .id').each(function (_, idNode) {
    const $id = $(idNode)
    const prereq_id = $id.text()

    if (prereq_id == id) {
      const $crit = $id.closest('.prerequisite_criterion')
      $crit.find('.name').text(name)
      const $prereqs = $id.closest('.prerequisites')
      const names = $.makeArray($prereqs.find('.prerequisite_criterion .name'))
        .map(el => $(el).text())
        .join(', ')
      $prereqs.find('.prerequisites_message').text(prerequisitesMessage(names))
    }
  })
}
const newPillMessage = function ($module, requirement_count) {
  const $message = $module.find('.requirements_message')
  $message.attr('data-requirement-type', requirement_count === 1 ? 'one' : 'all')

  if (requirement_count != 0) {
    const $pill = $('<ul class="pill"><li></li></ul></div>')
    $message.html($pill)
    const $pillMessage = $message.find('.pill li')
    const newPillMessageText =
      requirement_count === 1 ? I18n.t('Complete One Item') : I18n.t('Complete All Items')
    $pillMessage.text(newPillMessageText)
    $pillMessage.data('requirement-count', requirement_count)
  }
}

const updatePublishMenuDisabledState = function (disabled) {
  if (ENV.FEATURES.instui_header) {
    // Send event to ContextModulesHeader component to update the publish menu
    window.dispatchEvent(
      new CustomEvent('update-publish-menu-disabled-state', {detail: {disabled}}),
    )
  } else {
    // Update the top level publish menu to reflect the new module
    const publishMenu = document.getElementById('context-modules-publish-menu')
    if (publishMenu) {
      const $publishMenu = $(publishMenu)
      $publishMenu.data('disabled', disabled)

      if (!publishMenu.reactRoot) {
        publishMenu.reactRoot = createRoot(publishMenu)
      }
      publishMenu.reactRoot.render(
        <ContextModulesPublishMenu
          courseId={$publishMenu.data('courseId')}
          runningProgressId={$publishMenu.data('progressId')}
          disabled={disabled}
        />,
      )
    }
  }
}

modules.updatePublishMenuDisabledState = updatePublishMenuDisabledState
modules.relock_modules_dialog = new RelockModulesDialog()

modules.initModuleManagement = async function (duplicate) {
  const moduleItems = {}

  // Create the context modules backbone view to manage the publish button.
  new ContextModulesView({
    el: $('#content'),
    modules,
  })
  const relock_modules_dialog = modules.relock_modules_dialog

  const $context_module_unlocked_at = $('#context_module_unlock_at')
  let valCache = ''
  $('#unlock_module_at')
    .change(function () {
      const $this = $(this)
      const $unlock_module_at_details = $('.unlock_module_at_details')
      $unlock_module_at_details.showIf($this.prop('checked'))

      if ($this.prop('checked')) {
        if (!$context_module_unlocked_at.val()) {
          $context_module_unlocked_at.val(valCache)
        }
      } else {
        valCache = $context_module_unlocked_at.val()
        $context_module_unlocked_at.val('').triggerHandler('change')
      }
    })
    .triggerHandler('change')

  // -------- BINDING THE UPDATE EVENT -----------------
  $('.context_module').bind('update', (event, data) => {
    const $module = $('#context_module_' + data.context_module.id)
    $module.attr('data-module-id', data.context_module.id)
    $module.attr('aria-label', data.context_module.name)
    $module.find('.header').fillTemplateData({
      data: data.context_module,
      hrefValues: ['id'],
    })

    $module.find('.header').attr('id', data.context_module.id)
    $module.find('.footer').fillTemplateData({
      data: data.context_module,
      hrefValues: ['id'],
    })

    updateUnlockTime($module, data.context_module.unlock_at)
    updatePrerequisites($module, data.context_module.prerequisites)
    updateOtherPrerequisites(data.context_module.id, data.context_module.name)

    // Update requirement message pill
    if (data.context_module.completion_requirements.length === 0) {
      $module.find('.requirements_message').empty().attr('data-requirement-type', 'all')
    } else {
      newPillMessage($module, data.context_module.requirement_count)
    }

    $module
      .find('.context_module_items .context_module_item')
      .removeClass('progression_requirement')
      .removeClass('min_score_requirement')
      .removeClass('min_percentage_requirement')
      .removeClass('max_score_requirement')
      .removeClass('must_view_requirement')
      .removeClass('must_mark_done_requirement')
      .removeClass('must_submit_requirement')
      .removeClass('must_contribute_requirement')
      .find('.criterion')
      .removeClass('defined')

    // Hack. Removing the class here only to re-add it a few lines later if needed.
    $module.find('.ig-row').removeClass('with-completion-requirements')
    for (const idx in data.context_module.completion_requirements) {
      const req = data.context_module.completion_requirements[idx]
      req.criterion_type = req.type
      const $item = $module.find('#context_module_item_' + req.id)
      $item.find('.ig-row').addClass('with-completion-requirements')
      $item.find('.criterion').fillTemplateData({data: req})
      $item.find('.completion_requirement').fillTemplateData({data: req})
      $item.find('.criterion').addClass('defined')
      $item.find('.module-item-status-icon').show()
      $item.addClass(req.type + '_requirement').addClass('progression_requirement')
    }

    modules.refreshModuleList()
  })
  $('#completion_criterion_option .id').change(function () {
    const $option = $(this).parents('.completion_criterion_option')
    const data = $('#context_module_item_' + $(this).val()).getTemplateData({
      textValues: ['type', 'graded'],
    })
    $option
      .find('.type option')
      .hide()
      .prop('disabled', true)
      .end()
      .find('.type option.any')
      .show()
      .prop('disabled', false)
      .end()
      .find('.type option.' + data.type)
      .show()
      .prop('disabled', false)
    if (data.graded === '1') {
      $option.find('.type option.graded').show().prop('disabled', false)
    }
    if (data.criterion_type) {
      $option
        .find('.type')
        .val($option.find('.type option.' + data.criterion_type + ':first').val())
    }
    $option.find('.type').change()
  })

  $('#completion_criterion_option .type').change(function () {
    const $option = $(this).parents('.completion_criterion_option')

    // Show score text box and do some resizing of drop down to get it to stay on one line
    $option.find('.min_score_box').showIf($(this).val() === 'min_score')

    const id = $option.find('.id').val()
    const points_possible = $.trim(
      $('#context_module_item_' + id + ' .points_possible_display')
        .text()
        .split(' ')[0],
    )
    if (points_possible.length > 0 && $(this).val() === 'min_score') {
      $option.find('.points_possible').text(points_possible)
      $option.find('.points_possible_parent').show()
    } else {
      $option.find('.points_possible_parent').hide()
    }

    const itemName = $option.find('.id option:selected').text()
    const reqType = $option.find('.type option:selected').text()
    $option
      .closest('.criterion')
      .find('.delete_criterion_link')
      .attr(
        'aria-label',
        I18n.t('Delete requirement %{item} (%{type})', {item: itemName, type: reqType}),
      )
  })

  $(document).on('click', '.duplicate_module_link', function (event) {
    event.preventDefault()
    const duplicateRequestUrl = $(this).attr('href')
    const duplicatedModuleElement = $(this).parents('.context_module')
    const spinner = <ModuleDuplicationSpinner />
    const $tempElement = $('<div id="temporary-spinner" class="item-group-condensed"></div>')
    $tempElement.insertAfter(duplicatedModuleElement)

    const spinnerContainer = $('#temporary-spinner')[0]
    if (spinnerContainer) {
      if (!spinnerContainer.reactRoot) {
        spinnerContainer.reactRoot = createRoot(spinnerContainer)
      }
      spinnerContainer.reactRoot.render(spinner)
    }

    $.screenReaderFlashMessage(I18n.t('Duplicating Module, this may take some time'))
    const renderDuplicatedModule = function (response) {
      response.data.ENV_UPDATE.forEach(newAttachmentItem => {
        ENV.MODULE_FILE_DETAILS[newAttachmentItem.id] = newAttachmentItem
      })
      const newModuleId = response.data.context_module.id
      // This is terrible but then so is the whole file so it fits in
      const contextId = response.data.context_module.context_id
      const moduleName = response.data.context_module.name
      const modulesPage = ENV.FEATURE_MODULES_PERF
        ? `/courses/${contextId}/modules/${newModuleId}/module_html`
        : `/courses/${contextId}/modules`
      axios
        .get(modulesPage)
        .then(async getResponse => {
          const $newModule = ENV.FEATURE_MODULES_PERF
            ? $(getResponse.data)
            : $(getResponse.data).find(`#context_module_${newModuleId}`)
          spinnerContainer?.reactRoot?.unmount()
          $tempElement.remove()
          $newModule.insertAfter(duplicatedModuleElement)
          updateModuleFileDrop($newModule[0])
          $newModule.find('.collapse_module_link').focus()
          if (ENV.FEATURE_MODULES_PERF) {
            await modules.lazyLoadItems([parseInt(newModuleId, 10)])
          } else {
            modules.updateAssignmentData()
            modules.updateEstimatedDurations()
          }
          // Unbind event handlers with 'off' because they will get re-bound in initModuleManagement
          // and we don't want them to be called twice on click.
          $(document).off('click', '.delete_module_link')
          $(document).off('click', '.delete_item_link')
          $(document).off('click', '.duplicate_module_link')
          $(document).off('click', '.duplicate_item_link')
          if (!ENV.FEATURES.instui_header) {
            // not using with instui header, clicks are handled differently
            $(document).off('click', '.add_module_link')
          }
          $('#context_modules').off('addFileToModule')
          $newModule
            .find('.expand_module_link,.collapse_module_link')
            .bind('click keyclick', toggleModuleCollapse)
          modules.initModuleManagement($newModule)
        })
        .catch(showFlashError(I18n.t('Error rendering duplicated module')))
    }

    axios
      .post(duplicateRequestUrl, {})
      .then(renderDuplicatedModule)
      .catch(showFlashError(I18n.t('Error duplicating module')))
  })

  $(document).on('click', '.delete_module_link', function (event) {
    event.preventDefault()
    $(this)
      .parents('.context_module')
      .confirmDelete({
        url: $(this).attr('href'),
        message: I18n.t('confirm.delete', 'Are you sure you want to delete this module?'),
        cancelled() {
          $('.ig-header-admin .al-trigger', $(this)).focus()
        },
        success(data) {
          const id = data.context_module.id
          $('.context_module .prerequisites .criterion').each(function () {
            const criterion = $(this).getTemplateData({textValues: ['id', 'type']})
            if (criterion.type === 'context_module' && criterion.id == id) {
              $(this).remove()
            }
          })
          const $prevModule = $(this).prev()
          const $addModuleButton = ENV.FEATURES.instui_header
            ? $('#context-modules-header-add-module-button')
            : $('#content .header-bar .add_module_link')

          const $toFocus = $prevModule.length
            ? $('.ig-header-admin .al-trigger', $prevModule)
            : $addModuleButton
          removeEmptyModuleUI($(this)[0])
          $(this).slideUp(function () {
            $(this).remove()
            modules.updateTaggedItems()
            $toFocus.focus()
            const $contextModules = $('#context_modules .context_module')
            if (!$contextModules.length) {
              setExpandAllButtonVisible(false)
              updatePublishMenuDisabledState(true)
            }
          })
          $.flashMessage(
            I18n.t('Module %{module_name} was successfully deleted.', {
              module_name: data.context_module.name,
            }),
          )
        },
      })
  })

  $(document).on(
    'click',
    '.outdent_item_link,.indent_item_link',
    function (event, elem, activeElem) {
      event.preventDefault()
      const $elem = $(elem)
      const elemID =
        $elem && $elem.attr('id') ? '#' + $elem.attr('id') : elem && '.' + $elem.attr('class')
      const $cogLink = $(this).closest('.cog-menu-container').children('.al-trigger')
      const do_indent = $(this).hasClass('indent_item_link')
      const $item = $(this).parents('.context_module_item')
      let indent = modules.currentIndent($item)
      indent = Math.max(Math.min(indent + (do_indent ? 1 : -1), 5), 0)
      $item.loadingImage({image_size: 'small'})
      $.ajaxJSON(
        $(this).attr('href'),
        'PUT',
        {'content_tag[indent]': indent},
        data => {
          $item.loadingImage('remove')
          $item.removeClass((_, cls) => (cls.match(/indent_\d+/g) || []).join(' '))
          $item.addClass('indent_' + data.content_tag.indent)
          modules.updateAssignmentData()
          modules.updateEstimatedDurations()
        },
        _data => {},
      ).done(() => {
        if (elemID) {
          setTimeout(() => {
            const $activeElemClass = '.' + $(activeElem).attr('class').split(' ').join('.')
            $(elemID).find($activeElemClass).focus()
          }, 0)
        } else {
          $cogLink.focus()
        }
      })
    },
  )

  $(document).on('click', '.edit_item_link', function (event) {
    event.preventDefault()
    const $cogLink = $(this).closest('.cog-menu-container').children('.al-trigger')
    const $item = $(this).parents('.context_module_item')
    const data = $item.getTemplateData({
      textValues: [
        'url',
        'indent',
        'new_tab',
        'estimated_duration_minutes',
        'can_set_estimated_duration',
      ],
    })
    data.title = $item.find('.title').attr('title')
    data.indent = modules.currentIndent($item)
    $('#edit_item_form')
      .find('.external')
      .showIf($item.hasClass('external_url') || $item.hasClass('context_external_tool'))
    $('#edit_item_form').attr('action', $(this).attr('href'))
    $('#edit_item_form').fillFormData(data, {object_name: 'content_tag'})

    const $titleInput = $('#edit_item_form #content_tag_title')
    const restrictions = $item.data().master_course_restrictions
    const isDisabled =
      !get(ENV, 'MASTER_COURSE_SETTINGS.IS_MASTER_COURSE') && !!get(restrictions, 'content')
    $titleInput.prop('disabled', isDisabled)

    if (ENV.horizon_course) {
      if (data.can_set_estimated_duration === 'false') {
        $('#estimated_duration_edit').css({display: 'none'})
      } else {
        $('#estimated_duration_edit').css({display: 'table-row'})
      }
    }

    $('#edit_item_form')
      .dialog({
        title: I18n.t('titles.edit_item', 'Edit Item Details'),
        close() {
          $('#edit_item_form').hideErrors()
          $cogLink.focus()
        },
        open() {
          const titleClose = $(this).parent().find('.ui-dialog-titlebar-close')
          if (titleClose.length) {
            titleClose.trigger('focus')
          }
        },
        minWidth: 320,
        modal: true,
        zIndex: 1000,
      })
      .fixDialogButtons()
  })

  $('#edit_item_form .cancel_button').click(_event => {
    $('#edit_item_form').dialog('close')
  })

  $('#edit_item_form').formSubmit({
    beforeSubmit(data) {
      if (data['content_tag[title]'] == '') {
        $('#content_tag_title').errorBox(I18n.t('Title is required'))
        return false
      }
      $(this).loadingImage()
    },
    success(data) {
      $(this).loadingImage('remove')
      const $module = $('#context_module_' + data.content_tag.context_module_id)
      modules.addItemToModule($module, data.content_tag)
      $module.find('.context_module_items.ui-sortable').sortable('refresh')
      if (
        data.content_tag.content_id != 0 &&
        data.content_tag.content_type != 'ContextExternalTool'
      ) {
        modules.updateAllItemInstances(data.content_tag)
      }
      modules.updateAssignmentData()
      modules.updateEstimatedDurations()
      $(this).dialog('close')
    },
    error(data) {
      $(this).loadingImage('remove')
      $(this).formErrors(data)
    },
  })

  $(document).on('click', '.delete_item_link', function (event) {
    event.preventDefault()
    const $currentCogLink = $(this).closest('.cog-menu-container').children('.al-trigger')
    // Get the previous cog item to focus after delete
    const $allInCurrentModule = $(this).parents('.context_module_items').children()
    const $currentModule = $(this).parents('.context_module')
    const curIndex = $allInCurrentModule.index($(this).parents('.context_module_item'))
    const newIndex = curIndex - 1
    // Skip over headers, since they are not actionable
    let $placeToFocus
    if (newIndex >= 0) {
      const prevItem = $allInCurrentModule[newIndex]
      if ($(prevItem).hasClass('context_module_sub_header')) {
        $placeToFocus = $(prevItem).find('.cog-menu-container .al-trigger')
      } else {
        $placeToFocus = $(prevItem).find('.item_link')
      }
    } else {
      // Focus on the module cog since there are not more module item cogs
      $placeToFocus = $(this).closest('.editable_context_module').find('button.al-trigger')
    }
    $(this)
      .parents('.context_module_item')
      .confirmDelete({
        url: $(this).attr('href'),
        message: I18n.t(
          'confirm.delete_item',
          'Are you sure you want to remove this item from the module?',
        ),
        success(data) {
          delete ENV.MODULE_FILE_DETAILS[data.content_tag.id]
          $(this).slideUp(function () {
            $(this).remove()
            modules.updateTaggedItems()
            modules.updateEstimatedDurations()
            $placeToFocus.focus()
            refreshDuplicateLinkStatus($currentModule)

            const moduleId = $currentModule[0]?.dataset.moduleId
            if (ENV.FEATURE_MODULES_PERF && moduleId) {
              decrementModuleItemsCount(moduleId)
            }

            if (ENV.FEATURE_MODULES_PERF && isModuleCurrentPageEmpty($currentModule[0])) {
              loadFirstPage(moduleId)
            }
          })
          $.flashMessage(
            I18n.t('Module item %{module_item_name} was successfully removed.', {
              module_item_name: data.content_tag.title,
            }),
          )
        },
        cancelled() {
          $currentCogLink.focus()
        },
      })
  })

  $('.move_module_link').on('click keyclick', function (event) {
    event.preventDefault()

    const currentModule = $(this).parents('.context_module')[0]
    const modules = document.querySelectorAll('#context_modules .context_module')
    const siblings = Array.prototype.map.call(modules, module => {
      const id = module.getAttribute('id').substring('context_module_'.length)
      const title = module.querySelector('.header > .collapse_module_link > .name').textContent
      return {id, title}
    })

    const moveTrayProps = {
      title: I18n.t('Move Module'),
      items: [
        {
          id: currentModule.getAttribute('id').substring('context_module_'.length),
          title: currentModule.querySelector('.header > .collapse_module_link > .name').textContent,
        },
      ],
      moveOptions: {siblings},
      formatSaveUrl: () => `${ENV.CONTEXT_URL_ROOT}/modules/reorder`,
      onMoveSuccess: res => {
        const container = document.querySelector('#context_modules.ui-sortable')
        reorderElements(
          res.data.map(item => item.context_module.id),
          container,
          id => `#context_module_${id}`,
        )
        $(container).sortable('refresh')
      },
      focusOnExit: () => currentModule.querySelector('.al-trigger'),
    }

    renderTray(moveTrayProps, document.getElementById('not_right_side'))
  })

  $('.move_module_contents_link').on('click keyclick', async function (event) {
    event.preventDefault()

    const currentModule = $(this).parents('.context_module')[0]
    const modules = document.querySelectorAll('#context_modules .context_module')
    const groups = Array.prototype.map.call(modules, module => {
      const id = module.getAttribute('id').substring('context_module_'.length)
      const title = module.querySelector('.header > .collapse_module_link > .name').textContent
      let items = undefined
      if (hasAllItemsInTheDOM(module)) {
        const moduleItems = module.querySelectorAll('.context_module_item')
        items = Array.prototype.map.call(moduleItems, item => ({
          id: item.getAttribute('id').substring('context_module_item_'.length),
          title: item.querySelector('.title').textContent.trim(),
        }))
      }
      return {id, title, items}
    })
    const moduleId = currentModule.getAttribute('id').substring('context_module_'.length)
    let items = undefined
    if (hasAllItemsInTheDOM(currentModule)) {
      const moduleItems = currentModule.querySelectorAll('.context_module_item')
      items = Array.prototype.map.call(moduleItems, item => ({
        id: item.getAttribute('id').substring('context_module_item_'.length),
        title: item.querySelector('.title').textContent.trim(),
      }))
    } else {
      try {
        items = await fetchItemTitles(ENV.course_id, moduleId)
      } catch (_error) {
        return
      }
    }

    if (items.length === 0) {
      return
    }
    items[0].groupId = moduleId

    const moveTrayProps = {
      title: I18n.t('Move Contents Into'),
      items,
      moveOptions: {
        groupsLabel: I18n.t('Modules'),
        groups,
        excludeCurrent: true,
      },
      formatSaveUrl: ({groupId}) => `${ENV.CONTEXT_URL_ROOT}/modules/${groupId}/reorder`,
      onMoveSuccess: ({data, itemIds, groupId}) => {
        const targetModule = moduleFromId(groupId)

        if (ENV.FEATURE_MODULES_PERF && targetModule) {
          if (isModuleCollapsed(targetModule)) {
            expandModuleAndLoadAll(groupId)
          } else {
            loadAll(groupId)
          }
        } else {
          const $container = $(`#context_module_${groupId} .ui-sortable`)
          $container.sortable('disable')

          itemIds.forEach(id => {
            const item = document.querySelector(`#context_module_item_${id}`)
            $container[0].appendChild(item)
          })

          const order = data.context_module.content_tags.map(item => item.content_tag.id)
          reorderElements(order, $container[0], id => `#context_module_item_${id}`)

          $container.sortable('enable').sortable('refresh')
          updateModuleFileDrop(targetModule)
        }

        if (currentModule) {
          if (ENV.FEATURE_MODULES_PERF) {
            if (isModuleCollapsed(currentModule)) {
              // this gets rid of the items in a collapsed module
              expandModuleAndLoadAll(currentModule.dataset.moduleId)
            } else {
              // this gets rid of the paginator
              const ll = new ModuleItemsLazyLoader(ENV.course_id, () => {}, new ModuleItemsStore())
              ll.renderResult(currentModule.dataset.moduleId, '')

              // this gets rid of the show all/less button
              addShowAllOrLess(currentModule.dataset.moduleId)
            }
          } else {
            updateModuleFileDrop(currentModule)
          }
        }
      },
      focusOnExit: () => currentModule.querySelector('.al-trigger'),
    }

    renderTray(moveTrayProps, document.getElementById('not_right_side'))
  })

  $('.drag_and_drop_warning').on('focus', event => {
    $(event.currentTarget).removeClass('screenreader-only')
  })

  $('.drag_and_drop_warning').on('blur', event => {
    $(event.currentTarget).addClass('screenreader-only')
  })

  const add_module_link_handler = event => {
    event.preventDefault()
    const addModuleCallback = (data, $moduleElement) =>
      addModuleElement(
        data,
        $moduleElement,
        updatePublishMenuDisabledState,
        relock_modules_dialog,
        moduleItems,
      )
    modules.addModule(addModuleCallback)
  }

  if (ENV.FEATURES.instui_header) {
    // export "new module" handler for react
    document.add_module_link_handler = add_module_link_handler
  } else {
    // adds the "new module" button click handler
    $(document).on('click', '.add_module_link', add_module_link_handler)
  }

  // This allows ModuleFileDrop to create module items
  // once a file is uploaded. See ModuleFileDrop#handleDrop
  // for details on the custom event.
  $('#context_modules').on('addFileToModule', event => {
    event.preventDefault()
    const moduleId = event.originalEvent.moduleId
    const attachment = event.originalEvent.attachment
    const returnToFileDrop = event.originalEvent.returnToFileDrop
    const item_data = {
      'item[id]': attachment.id,
      'item[type]': 'attachment',
      'item[title]': attachment.display_name,
    }
    generate_submit(moduleId, false, returnToFileDrop)(item_data)
  })

  $('.add_module_item_link').on('click', function (event) {
    event.preventDefault()
    const $trigger = $(event.currentTarget)
    $trigger.blur()
    const $module = $(this).closest('.context_module')
    if ($module.hasClass('collapsed_module')) {
      $module.find('.expand_module_link').triggerHandler('click', () => {
        $module.find('.add_module_item_link').click()
      })
      return
    }

    const id = $(this).parents('.context_module').find('.header').attr('id')
    const name = $(this).parents('.context_module').find('.name').attr('title')
    const options = {for_modules: true, context_module_id: id}
    const midSizeModal = window.matchMedia('(min-width: 500px)').matches
    const fullSizeModal = window.matchMedia('(min-width: 770px)').matches
    const responsiveWidth = fullSizeModal ? 770 : midSizeModal ? 500 : 320
    options.select_button_text = I18n.t('buttons.add_item', 'Add Item')
    options.holder_name = name
    options.height = 550
    options.width = responsiveWidth
    options.dialog_title = I18n.t('titles.add_item', 'Add Item to %{module}', {module: name})
    options.close = function () {
      $trigger.focus()
    }

    options.submit = generate_submit(id)
    selectContentDialog(options)
  })

  function generate_submit(id, focusLink = true, returnToFileDrop = false) {
    return item_data => {
      // a content item with an assignment_id means that an assignment was already created
      // on the backend, so no module item should be created now. Reload the page to show
      // the newly created assignment
      if (item_data['item[assignment_id]']) {
        return window.location.reload()
      }

      const $module = $('#context_module_' + id)
      let $item
      if (!ENV.FEATURE_MODULES_PERF) {
        let nextPosition = modules.getNextPosition($module)
        item_data.content_details = ['items']
        item_data['item[position]'] = nextPosition++
        $item = modules.addItemToModule($module, item_data)
      }
      $module.find('.context_module_items.ui-sortable').sortable('refresh').sortable('disable')
      const url = $module.find('.add_module_item_link').attr('rel')
      $module.disableWhileLoading(
        $.ajaxJSON(url, 'POST', item_data, data => {
          if (ENV.FEATURE_MODULES_PERF) {
            maybeExpandAndLoadAll(id, true)
            modules.addContentTagToEnv(data.content_tag)
          } else {
            $item?.remove()
            data.content_tag.type = item_data['item[type]']
            $item = modules.addItemToModule($module, data.content_tag)
            modules.addContentTagToEnv(data.content_tag)
            $module.find('.context_module_items.ui-sortable').sortable('enable').sortable('refresh')
            initNewItemPublishButton($item, data.content_tag)
            initNewItemDirectShare($item, data.content_tag)
            modules.updateAssignmentData()
            modules.updateEstimatedDurations()

            $item.find('.lock-icon').data({
              moduleType: data.content_tag.type,
              contentId: data.content_tag.content_id,
              moduleItemId: data.content_tag.id,
            })
            modules.loadMasterCourseData(data.content_tag.id)
          }
        }),
        {
          onComplete() {
            if (focusLink) {
              $module.find('.add_module_item_link').focus()
            } else if (returnToFileDrop) {
              const itemList = $module.find('ul.context_module_items')
              const focusItem = itemList.find("a[role='button']")
              focusItem?.focus()
            }
          },
        },
      )
    }
  }

  $(document).on('click', '.duplicate_item_link', function (event) {
    event.preventDefault()

    const $module = $(this).closest('.context_module')
    const url = $(this).attr('href')

    axios
      .post(url)
      .then(({data}) => {
        if (ENV.FEATURE_MODULES_PERF) {
          maybeExpandAndLoadAll($module.data('moduleId'))
        } else {
          const $item = modules.addItemToModule($module, data.content_tag)
          initNewItemPublishButton($item, data.content_tag)
          initNewItemDirectShare($item, data.content_tag)

          modules.updateAssignmentData()
          modules.updateEstimatedDurations()

          $item.find('.lock-icon').data({
            moduleType: data.content_tag.type,
            contentId: data.content_tag.content_id,
            moduleItemId: data.content_tag.id,
          })
          modules.loadMasterCourseData(data.content_tag.id)

          $module.find('.context_module_items.ui-sortable').sortable('disable')
          data.new_positions.forEach(({content_tag}) => {
            $module.find(`#context_module_item_${content_tag.id}`).fillTemplateData({
              data: {position: content_tag.position},
            })
          })
          $(`#context_module_item_${data.content_tag.id} .item_link`).focus()
          $module.find('.context_module_items.ui-sortable').sortable('enable').sortable('refresh')
        }
      })
      .catch(showFlashError('Error duplicating item'))
  })

  $('#add_module_prerequisite_dialog .cancel_button').click(() => {
    $('#add_module_prerequisite_dialog').dialog('close')
  })

  $(document).on('click', '.delete_prerequisite_link', function (event) {
    event.preventDefault()
    const $criterion = $(this).parents('.criterion')
    const prereqs = []

    $(this)
      .parents('.context_module .prerequisites .criterion')
      .each(function () {
        if ($(this)[0] != $criterion[0]) {
          const data = $(this).getTemplateData({textValues: ['id', 'type']})
          const type = data.type === 'context_module' ? 'module' : data.type
          prereqs.push(type + '_' + data.id)
        }
      })

    const url = $(this).parents('.context_module').find('.edit_module_link').attr('href')
    const data = {'context_module[prerequisites]': prereqs.join(',')}

    $criterion.dim()

    $.ajaxJSON(url, 'PUT', data, data => {
      $('#context_module_' + data.context_module.id).triggerHandler('update', data)
    })
  })
  $('#add_module_prerequisite_dialog .submit_button').click(function () {
    const val = $('#add_module_prerequisite_dialog .prerequisite_module_select select').val()
    if (!val) {
      return
    }
    $('#add_module_prerequisite_dialog').loadingImage()
    const prereqs = []
    prereqs.push('module_' + val)
    const $module = $(
      '#context_module_' +
        $('#add_module_prerequisite_dialog').getTemplateData({textValues: ['context_module_id']})
          .context_module_id,
    )
    $module.find('.prerequisites .criterion').each(function () {
      prereqs.push('module_' + $(this).getTemplateData({textValues: ['id', 'name', 'type']}).id)
    })
    const url = $module.find('.edit_module_link').attr('href')
    const data = {'context_module[prerequisites]': prereqs.join(',')}
    $.ajaxJSON(
      url,
      'PUT',
      data,
      data => {
        $('#add_module_prerequisite_dialog').loadingImage('remove')
        $('#add_module_prerequisite_dialog').dialog('close')
        $('#context_module_' + data.context_module.id).triggerHandler('update', data)
      },
      data => {
        $('#add_module_prerequisite_dialog').loadingImage('remove')
        $('#add_module_prerequisite_dialog').formErrors(data)
      },
    )
  })

  requestAnimationFrame(function () {
    const items = Array.from(document.querySelectorAll('#context_modules .context_module_items'))
    const next = function () {
      if (items.length > 0) {
        const $item = $(items.shift())
        const opts = modules.sortable_module_options
        const k5TabsContainer = $('#k5-course-header').closest('.ic-Dashboard-tabs').eq(0)
        const k5ModulesContainer = $('#k5-modules-container')
        if (k5TabsContainer.length > 0 && k5ModulesContainer.length > 0) {
          opts.sort = event => onContainerOverlapped(event, k5ModulesContainer, k5TabsContainer)
        }
        opts.update = modules.updateModuleItemPositions
        $item.sortable(opts)
        requestAnimationFrame(next)
      }
    }
    next()
    $('#context_modules').sortable({
      handle: '.reorder_module_link',
      helper: 'clone',
      axis: 'y',
      update: modules.updateModulePositions,
    })
    modules.refreshModuleList()
    modules.refreshed = true
  })

  function initNewItemPublishButton($item, data) {
    const publishData = {
      moduleType: data.type,
      id: data.publishable_id,
      moduleItemName: data.moduleItemName || data.title,
      moduleItemId: data.id,
      moduleId: data.context_module_id,
      courseId: data.context_id,
      published: data.published,
      publishable: data.publishable,
      unpublishable: data.unpublishable,
      publishAt: data.publish_at,
      content_details: data.content_details,
      isNew: true,
    }

    const view = initPublishButton($item.find('.publish-icon'), publishData)
    overrideModel(moduleItems, relock_modules_dialog, view.model, view)
  }

  function initNewItemDirectShare($item, data) {
    const $copyToMenuItem = $item.find('.module_item_copy_to')
    if ($copyToMenuItem.length === 0) return // feature not enabled, probably
    const $sendToMenuItem = $item.find('.module_item_send_to')
    const content_id = data.content_id
    const content_type = data.type.replace(/^wiki_/, '')
    const select_class = content_type === 'quiz' ? 'quizzes' : `${content_type}s`
    if (['assignment', 'discussion_topic', 'page', 'quiz'].includes(content_type)) {
      // make the direct share menu items work!
      $copyToMenuItem.data('select-class', select_class)
      $copyToMenuItem.data('select-id', content_id)
      $sendToMenuItem.data('content-type', content_type)
      $sendToMenuItem.data('content-id', content_id)
    } else {
      // not direct shareable; remove the menu items
      $copyToMenuItem.closest('li').remove()
      $sendToMenuItem.closest('li').remove()
    }
  }

  if (duplicate && duplicate.length) {
    const modulePublishIcon = duplicate[0].querySelector('.module-publish-icon')
    if (modulePublishIcon) {
      const courseId = modulePublishIcon.getAttribute('data-course-id')
      const moduleId = modulePublishIcon.getAttribute('data-module-id')
      const published = modulePublishIcon.getAttribute('data-published') === 'true'
      renderContextModulesPublishIcon(courseId, moduleId, false, published)
    }
  }

  $('.module-publish-link').each((i, element) => {
    const $el = $(element)
    const model = new Publishable(
      {published: $el.hasClass('published'), id: $el.attr('data-id')},
      {url: $el.attr('data-url'), root: 'module'},
    )
    const view = new PublishButtonView({model, el: $el})
    view.render()
  })
  // I tried deferring the rendering of ContextModulesPuyblishMenu
  // and ContextModulesPublishIcons until here,
  // after the models and views were all setup, but it made
  // the UI janky. Let them get rendered early, the tell
  // ContextModulesPublishMenu everything is ready.
  window.dispatchEvent(new Event('module-publish-models-ready'))
}

function toggleModuleCollapse(event, fetchAllPages) {
  event.preventDefault()
  const expandCallback = null
  const collapse = $(this).hasClass('collapse_module_link') ? '1' : '0'
  const $module = $(this).parents('.context_module')
  const reload_entries =
    fetchAllPages ||
    ($module.find('.content .context_module_items').children().length === 0 &&
      $module.find('.module_dnd').length === 0)
  const toggle = function (show) {
    const callback = function () {
      $module
        .find('.collapse_module_link')
        .css('display', $module.find('.content:visible').length > 0 ? 'inline-block' : 'none')
      $module
        .find('.expand_module_link')
        .css('display', $module.find('.content:visible').length === 0 ? 'inline-block' : 'none')
      if ($module.find('.content:visible').length > 0) {
        $module.find('.footer .manage_module').css('display', '')
        $module.toggleClass('collapsed_module', false)
        // Makes sure the resulting item has focus.
        $module.find('.collapse_module_link').focus()
        $.screenReaderFlashMessage(I18n.t('Expanded'))
      } else {
        $module.find('.footer .manage_module').css('display', '') // 'none');
        $module.toggleClass('collapsed_module', true)
        // Makes sure the resulting item has focus.
        $module.find('.expand_module_link').focus()
        $.screenReaderFlashMessage(I18n.t('Collapsed'))
      }
      setExpandAllButton()
      if (expandCallback && $.isFunction(expandCallback)) {
        expandCallback()
      }
      if (ENV.FEATURE_MODULES_PERF) {
        addShowAllOrLess($module.data('moduleId'))
      }
    }
    if (show) {
      $module.find('.content').show()
      callback()
    } else {
      $module.find('.content').slideToggle(callback)
    }
  }
  if (reload_entries) {
    $module.loadingImage()
  }
  const url = $(this).attr('href')
  $.ajaxJSON(
    url,
    'POST',
    {collapse},
    async data => {
      if (reload_entries) {
        if (ENV.FEATURE_MODULES_PERF) {
          await modules.lazyLoadItems([parseInt($module.data('moduleId'), 10)], fetchAllPages)
          $module.loadingImage('remove')
        } else {
          $module.loadingImage('remove')
          for (const idx in data) {
            modules.addItemToModule($module, data[idx].content_tag)
          }
          $module.find('.context_module_items.ui-sortable').sortable('refresh')
        }
        toggle()
        updateProgressionState($module)
      }
    },
    _data => {
      $module.loadingImage('remove')
    },
  )
  if (collapse === '1' || !reload_entries) {
    toggle()
  }
}

function moduleContentIsHidden(contentEl) {
  return (
    contentEl.style.display === 'none' ||
    contentEl.parentElement.classList.contains('collapsed_module')
  )
}

function updateSubAssignmentData(contextModuleItem, subAssignments) {
  subAssignments.forEach(subAssignment => {
    const replyToTopicElement = contextModuleItem.find('.reply_to_topic_display')
    if (!replyToTopicElement.length && !ENV.IS_STUDENT) {
      // prepending reply to topic last so that it is listed first
      contextModuleItem
        .find('.ig-details')
        .prepend('<div class="ig-details__item reply_to_entry_display"></div>')
      contextModuleItem
        .find('.ig-details')
        .prepend('<div class="ig-details__item reply_to_topic_display"></div>')
    }
    const title =
      subAssignment.sub_assignment_tag === 'reply_to_topic'
        ? I18n.t('Reply to Topic')
        : I18n.t('Required Replies (%{required_replies})', {
            required_replies: subAssignment.replies_required,
          })
    let dueDate = ''
    if (!(ENV.IN_PACED_COURSE && !ENV.IS_STUDENT)) {
      if (subAssignment.has_many_overrides != null) {
        dueDate = I18n.t('Multiple Due Dates')
      } else if (subAssignment.vdd_tooltip != null) {
        subAssignment.vdd_tooltip.link_href = contextModuleItem.find('a.title').attr('href')
        dueDate = vddTooltipView(subAssignment.vdd_tooltip)
      } else if (subAssignment.due_date) {
        dueDate = dateString(subAssignment.due_date)
      } else {
        dueDate = I18n.t('No Due Date')
      }
      contextModuleItem
        .find(`.${subAssignment.sub_assignment_tag}_display`)
        .html(`<b>${title}:</b> ${dueDate}`)
    } else {
      contextModuleItem.find(`.${subAssignment.sub_assignment_tag}_display`).html(`<b>${title}</b>`)
    }
  })
}

// need the assignment data to check past due state
if (!ENV.FEATURE_MODULES_PERF || ENV.IS_STUDENT) {
  modules.updateAssignmentData(() => {
    modules.updateProgressions(modules.afterUpdateProgressions)
  })
}

// Post process lazy loaded module items ----------------------
function initContextModuleItems(moduleId) {
  const $module = moduleId ? $(`#context_module_${moduleId}`) : $('#context_modules')

  if (ENV.IS_STUDENT) {
    $module.find('.context_module_item .ig-row').addClass('student-view')
  }

  $module.find('.context_module_item').each((_i, $item) => {
    modules.evaluateItemCyoe($item)
  })

  $module.find('.publish-icon').each((_index, el) => {
    const $el = $(el)
    if ($el.data('id')) {
      const view = initPublishButton($el)
      overrideModel({}, modules.relock_modules_dialog, view.model, view)
    }
  })

  const opts = modules.sortable_module_options
  opts.update = modules.updateModuleItemPositions
  $module.find('.context_module_items').sortable(opts)
  // NOTE: This takes an extraordinary amount of time, and without it
  //       I have not seen any issues with drag-and-drop ordering
  //       of module items
  // $('#context_modules.ui-sortable').sortable('refresh')
  // $('#context_modules .context_module .context_module_items.ui-sortable').each(function () {
  //   $(this).sortable('refresh')
  //   $(this).sortable('option', 'connectWith', '.context_module_items')
  // })

  $module.find('.move_module_item_link').on('click keyclick', function (event) {
    event.preventDefault()

    const currentItem = $(this).parents('.context_module_item')[0]
    const currentModule = $(this).parents('.context_module')[0]
    const modules = document.querySelectorAll('#context_modules .context_module')
    const groups = Array.from(modules).map(module => {
      const id = module.getAttribute('id').substring('context_module_'.length)
      const title = module.querySelector('.header > .collapse_module_link > .name').textContent
      if (ENV.FEATURE_MODULES_PERF && (isModuleCollapsed(module) || isModulePaginated(module))) {
        return {id, title, items: undefined}
      }
      const moduleItems = module.querySelectorAll('.context_module_item')
      const items = Array.from(moduleItems).map(item => ({
        id: item.getAttribute('id').substring('context_module_item_'.length),
        title: item.querySelector('.title').textContent.trim(),
      }))
      return {id, title, items}
    })

    const moveTrayProps = {
      title: I18n.t('Move Module Item'),
      items: [
        {
          id: currentItem.getAttribute('id').substring('context_module_item_'.length),
          title: currentItem.querySelector('.title').textContent.trim(),
        },
      ],
      moveOptions: {
        groupsLabel: I18n.t('Modules'),
        groups,
      },
      formatSaveUrl: ({groupId}) => `${ENV.CONTEXT_URL_ROOT}/modules/${groupId}/reorder`,
      onMoveSuccess: ({data, itemIds, groupId}) => {
        const itemId = itemIds[0]
        const item = document.querySelector(`#context_module_item_${itemId}`)
        const $container = $(`#context_module_${groupId} .ui-sortable`)
        if ($container.length) {
          $container.sortable('disable')
          $container[0].appendChild(item)

          const order = data.context_module.content_tags.map(item => item.content_tag.id)
          reorderElements(order, $container[0], id => `#context_module_item_${id}`)
          $container.sortable('enable').sortable('refresh')
        } else {
          item.remove()
        }
        if (ENV.FEATURE_MODULES_PERF) {
          maybeExpandAndLoadAll(groupId, true)
        }
        updateModuleFileDrop(document.querySelector(`#context_module_${groupId}`))
        updateModuleFileDrop(currentModule)
      },
      focusOnExit: () => currentItem.querySelector('.al-trigger'),
    }

    renderTray(moveTrayProps, document.getElementById('not_right_side'))
  })

  if (ENV.FEATURE_MODULES_PERF) {
    addShowAllOrLess(moduleId)
  }
}

// I don't think this is a long-term solution. We're going to need access
// to all the assignment's data (due due dates, availability, etc)
function parseModuleItemElement(element) {
  const pointsPossibleElem = element?.querySelector('.points_possible_display')
  const points = parseFloat(pointsPossibleElem?.textContent)

  return {pointsPossible: isNaN(points) ? undefined : points}
}

function handleRemoveDueDateInput(itemProps) {
  switch (itemProps.moduleItemType) {
    case 'discussion':
    case 'discussion_topic':
      if (itemProps.moduleItemHasAssignment === 'true') {
        return false
      } else return true
    case 'page':
    case 'wiki_page':
      return true
    default:
      return false
  }
}

function renderItemAssignToTray(open, returnFocusTo, itemProps) {
  const container = document.getElementById('differentiated-modules-mount-point')
  if (container.reactRoot) container.reactRoot.unmount()
  container.reactRoot = createRoot(container)
  container.reactRoot.render(
    <ItemAssignToManager
      open={open}
      onClose={() => {
        container.reactRoot.unmount()
      }}
      onDismiss={() => {
        container.reactRoot.unmount()
        returnFocusTo.focus()
      }}
      courseId={itemProps.courseId}
      itemName={itemProps.moduleItemName}
      itemType={itemProps.moduleItemType}
      iconType={itemProps.moduleItemType}
      itemContentId={itemProps.moduleItemContentId}
      pointsPossible={itemProps.pointsPossible}
      locale={ENV.LOCALE || 'en'}
      timezone={ENV.TIMEZONE || 'UTC'}
      removeDueDateInput={handleRemoveDueDateInput(itemProps)}
      isCheckpointed={itemProps.moduleItemHasCheckpoint === 'true'}
    />,
  )
}

function renderCopyToTray(open, contentSelection, returnFocusTo) {
  const mountPoint = document.getElementById('direct-share-mount-point')
  if (!mountPoint) return
  if (!mountPoint.reactRoot) {
    mountPoint.reactRoot = createRoot(mountPoint)
  }
  mountPoint.reactRoot.render(
    <DirectShareCourseTray
      open={open}
      sourceCourseId={ENV.COURSE_ID}
      contentSelection={contentSelection}
      onDismiss={() => {
        renderCopyToTray(false, contentSelection, returnFocusTo)
        returnFocusTo.focus()
      }}
    />,
  )
}

function renderSendToTray(open, contentSelection, returnFocusTo) {
  const mountPoint = document.getElementById('direct-share-mount-point')
  if (!mountPoint) return
  if (!mountPoint.reactRoot) {
    mountPoint.reactRoot = createRoot(mountPoint)
  }
  mountPoint.reactRoot.render(
    <DirectShareUserModal
      open={open}
      sourceCourseId={ENV.COURSE_ID}
      contentShare={contentSelection}
      onDismiss={() => {
        renderSendToTray(false, contentSelection, returnFocusTo)
        returnFocusTo.focus()
      }}
    />,
  )
}

function renderExternalAppsTray(open, contentSelection, moduleId, returnFocusTo) {
  const mountPoint = document.getElementById('direct-share-mount-point')
  if (!mountPoint) return
  if (!mountPoint.reactRoot) {
    mountPoint.reactRoot = createRoot(mountPoint)
  }
  mountPoint.reactRoot.render(
    <ExternalAppsMenuTray
      open={open}
      sourceCourseId={ENV.COURSE_ID}
      contentSelection={contentSelection}
      moduleId={moduleId}
      onDismiss={() => {
        renderExternalAppsTray(false, contentSelection, moduleId, returnFocusTo)
        returnFocusTo.focus()
      }}
    />,
  )
}

// --------------------------------------------------------

function initContextModules() {
  $('.context_module').each(function () {
    refreshDuplicateLinkStatus($(this))
  })

  if (ENV.IS_STUDENT) {
    $('.context_module').addClass('student-view')
  }

  if (ENV.horizon_course) {
    modules.updateEstimatedDurations()
  }

  // I cannot find anywhere that these classname is added to the modules dom
  // Skipping this when lazy loading items
  if (!ENV.FEATURE_MODULES_PERF) {
    $('.external_url_link').click(function (event) {
      Helper.externalUrlLinkClick(event, $(this))
    })

    renderDatetimeField($('.datetime_field'))
  }

  $(document).on('mouseover', '.context_module', function () {
    $('.context_module_hover').removeClass('context_module_hover')
    $(this).addClass('context_module_hover')
  })

  $(document).on('mouseover focus', '.context_module_item', function () {
    $('.context_module_item_hover').removeClass('context_module_item_hover')
    $(this).addClass('context_module_item_hover')
  })

  if (ENV.FEATURES.instui_header) {
    // render the new INSTUI header component
    renderHeaderComponent(ENV.EXPANDED_MODULES.length > 0)
  }

  let $currentElem = null
  const hover = function ($elem) {
    if ($elem.hasClass('context_module')) {
      $('.context_module_hover').removeClass('context_module_hover')
      $('.context_module_item_hover').removeClass('context_module_item_hover')
      $elem.addClass('context_module_hover')
    } else if ($elem.hasClass('context_module_item')) {
      $('.context_module_item_hover').removeClass('context_module_item_hover')
      $('.context_module_hover').removeClass('context_module_hover')
      $elem.addClass('context_module_item_hover')
      $elem.parents('.context_module').addClass('context_module_hover')
    }
    $elem.find(':tabbable:first').focus()
  }

  // This method will select the items passed in with the options object
  // and can be used to advance the focus or return to the previous module or module_item
  // This will also return the element that is now in focus
  const selectItem = function (options) {
    options = options || {}
    let $elem

    if (!$currentElem) {
      $elem = $('.context_module:first')
    } else if ($currentElem && $currentElem.hasClass('context_module')) {
      $elem = options.selectWhenModuleFocused && options.selectWhenModuleFocused.item
      $elem = $elem.length
        ? $elem
        : options.selectWhenModuleFocused && options.selectWhenModuleFocused.fallbackModule
    } else if ($currentElem && $currentElem.hasClass('context_module_item')) {
      $elem = options.selectWhenModuleItemFocused && options.selectWhenModuleItemFocused.item
      $elem = $elem.length
        ? $elem
        : options.selectWhenModuleItemFocused && options.selectWhenModuleItemFocused.fallbackModule
    }

    hover($elem)
    return $elem
  }

  const getClosestModuleOrItem = function ($currentElem) {
    const selector =
      $currentElem && $currentElem.closest('.context_module_item_hover').length
        ? '.context_module_item_hover'
        : '.context_module_hover'
    return $currentElem.closest(selector)
  }

  // Keyboard Shortcuts:
  // "k" and "up arrow" move the focus up between modules and module items
  if (!ENV.disable_keyboard_shortcuts) {
    const $document = $(document)
    $document.keycodes('k up', _event => {
      // If the vertical kebob pop-up menu is open then ignore the shortcut
      if ($('.ui-menu.ui-state-open').length) return

      const params = {
        selectWhenModuleFocused: {
          item:
            $currentElem &&
            $currentElem.prev('.context_module').find('.context_module_item:visible:last'),
          fallbackModule: $currentElem && $currentElem.prev('.context_module'),
        },
        selectWhenModuleItemFocused: {
          item: $currentElem && $currentElem.prev('.context_module_item:visible'),
          fallbackModule: $currentElem && $currentElem.parents('.context_module'),
        },
      }
      const $elem = selectItem(params)
      if ($elem.length) $currentElem = $elem
    })

    // "j" and "down arrow" move the focus down between modules and module items
    $document.keycodes('j down', _event => {
      // If the vertical kebob pop-up menu is open then ignore the shortcut
      if ($('.ui-menu.ui-state-open').length) return

      const params = {
        selectWhenModuleFocused: {
          item: $currentElem && $currentElem.find('.context_module_item:visible:first'),
          fallbackModule: $currentElem && $currentElem.next('.context_module'),
        },
        selectWhenModuleItemFocused: {
          item: $currentElem && $currentElem.next('.context_module_item:visible'),
          fallbackModule:
            $currentElem && $currentElem.parents('.context_module').next('.context_module'),
        },
      }
      const $elem = selectItem(params)
      if ($elem.length) $currentElem = $elem
    })

    // "e" opens up Edit Module Settings form if focus is on Module or Edit Item Details form if focused on Module Item
    // "d" deletes module or module item
    // "space" opens up Move Item or Move Module form depending on which item is focused
    $document.keycodes('e d space', event => {
      if (!$currentElem) return

      const $elem = getClosestModuleOrItem($currentElem)
      const $hasClassItemHover = $elem.hasClass('context_module_item_hover')

      if (event.keyString === 'e') {
        $hasClassItemHover
          ? $currentElem.find('.edit_item_link:first').click()
          : $currentElem.find('.edit_module_link:first').click()
      } else if (event.keyString === 'd') {
        if ($hasClassItemHover) {
          $currentElem.find('.delete_item_link:first').click()
          $currentElem = $currentElem.parents('.context_module')
        } else {
          $currentElem.find('.delete_module_link:first').click()
          $currentElem = null
        }
      } else if (event.keyString === 'space') {
        $hasClassItemHover
          ? $currentElem.find('.move_module_item_link:first').click()
          : $currentElem.find('.move_module_link:first').click()
      }

      event.preventDefault()
    })

    // "n" opens up the Add Module form
    $document.keycodes('n', event => {
      if (ENV.FEATURES.instui_header) {
        // handles the "new module" button action on keypress
        $('#context-modules-header-add-module-button:visible').click()
      } else {
        $('.add_module_link:visible:first').click()
      }

      event.preventDefault()
    })

    // "i" indents module item
    // "o" outdents module item
    $document.keycodes('i o', event => {
      if (!$currentElem) return

      const $currentElemID = $currentElem.attr('id')

      if (event.keyString === 'i') {
        $currentElem
          .find('.indent_item_link:first')
          .trigger('click', [$currentElem, document.activeElement])
      } else if (event.keyString === 'o') {
        $currentElem
          .find('.outdent_item_link:first')
          .trigger('click', [$currentElem, document.activeElement])
      }

      $document.ajaxStop(() => {
        $currentElem = $('#' + $currentElemID)
      })
    })
  }

  if ($('#context_modules').hasClass('editable')) {
    requestAnimationFrame(() => {
      modules.initModuleManagement()
    })
  }

  $('.context_module')
    .find('.expand_module_link,.collapse_module_link')
    .bind('click keyclick', toggleModuleCollapse)
  $(document).fragmentChange((_event, hash) => {
    if (hash === '#student_progressions') {
      $('.module_progressions_link').trigger('click')
    } else if (!hash.startsWith('#!')) {
      const module = $(hash.replace(/module/, 'context_module'))
      if (module.hasClass('collapsed_module')) {
        module.find('.expand_module_link').triggerHandler('click')
      }
    }
  })

  // from context_modules/_content
  const collapsedModules = ENV.COLLAPSED_MODULES
  for (const idx in collapsedModules) {
    $('#context_module_' + collapsedModules[idx]).addClass('collapsed_module')
  }

  const $contextModules = $('#context_modules .context_module')
  if (!$contextModules.length) {
    $('#no_context_modules_message').show()
    setExpandAllButtonVisible(false)
    $('#context_modules_sortable_container').addClass('item-group-container--is-empty')
  }
  $contextModules.each(function () {
    updateProgressionState($(this))
  })

  setExpandAllButton()

  if (!ENV.FEATURES.instui_header) {
    setExpandAllButtonHandler(expandCollapseAllButtonHandler)
  }

  // this is the callback after the expand/collapse all button is clicked
  // when the instui header is NOT enabled
  async function expandCollapseAllButtonHandler(expanding) {
    if (expanding && ENV.FEATURE_MODULES_PERF) {
      const moduleSelector = '.context_module.collapsed_module:not(#context_module_blank)'
      const moduleIds = Array.from(document.querySelectorAll(moduleSelector)).map(
        d => d.dataset.moduleId,
      )
      await modules.lazyLoadItems(moduleIds)
    }
    $('#expand_collapse_all').prop('disabled', false)
  }

  // This is the onClick handler for the expand/collapse all button
  // when the instui header is enabled
  function expandCollapseAllButtonHandler_instui_header() {
    const moduleCount = document.querySelectorAll(
      '.context_module:not(#context_module_blank)',
    ).length
    const collapsedModuleCount = document.querySelectorAll(
      '.context_module.collapsed_module:not(#context_module_blank)',
    ).length
    const shouldExpand = collapsedModuleCount === moduleCount
    const moduleSelector = shouldExpand
      ? '.context_module.collapsed_module:not(#context_module_blank)'
      : '.context_module:not(#context_module_blank)'
    const moduleIds = Array.from(document.querySelectorAll(moduleSelector)).map(
      d => d.dataset.moduleId,
    )

    // logic copied from utils.jsx setExpandAllButtonHandler
    moduleIds.forEach(moduleId => {
      const $module = $(`#context_module_${moduleId}`)
      if (
        (shouldExpand && $module.find('.content:visible').length === 0) ||
        (!shouldExpand && $module.find('.content:visible').length > 0)
      ) {
        const callback = function () {
          $module
            .find('.collapse_module_link')
            .css('display', shouldExpand ? 'inline-block' : 'none')
          $module.find('.expand_module_link').css('display', shouldExpand ? 'none' : 'inline-block')
          $module.find('.footer .manage_module').css('display', '')
          $module.toggleClass('collapsed_module', !shouldExpand)
          if (ENV.FEATURE_MODULES_PERF) {
            addShowAllOrLess($module.data('module-id'))
          }
        }
        $module.find('.content').slideToggle({
          queue: false,
          done: callback,
        })
      }
    })

    const url = `/courses/${ENV.COURSE_ID}/collapse_all_modules`
    const collapse = shouldExpand ? '0' : '1'
    $.ajaxJSON(url, 'POST', {collapse}, _data => {
      if (shouldExpand && ENV.FEATURE_MODULES_PERF && moduleIds.length > 0) {
        modules.lazyLoadItems(moduleIds)
      }
    })
    renderHeaderComponent(shouldExpand) // this looks wrong, but shouldExpand is set before we do the work
  }

  if (!ENV.FEATURES.instui_header) {
    // menu tools click handler for the old UI
    $('.menu_tray_tool_link').click(openExternalTool)
  }

  function renderHeaderComponent(anyModuleExpanded) {
    const root = $('#context-modules-header-root')
    if (!root.length) return
    const mountPoint = root[0]
    if (!mountPoint.reactRoot) {
      mountPoint.reactRoot = createRoot(mountPoint)
    }
    mountPoint.reactRoot.render(
      <ContextModulesHeader
        {...root.data('props')}
        expandCollapseAll={{
          onExpandCollapseAll: expandCollapseAllButtonHandler_instui_header,
          anyModuleExpanded,
        }}
      />,
    )
  }

  $(document).on('click', '.module_copy_to', event => {
    event.preventDefault()
    const moduleId = $(event.target).closest('.context_module').data('module-id').toString()
    const selection = {modules: [moduleId]}
    const returnFocusTo = $(event.target).closest('ul').prev('.al-trigger')
    renderCopyToTray(true, selection, returnFocusTo)
  })

  if (window.ENV.FEATURES?.create_external_apps_side_tray_overrides) {
    $(document).on('click', '.module_external_apps', event => {
      event.preventDefault()
      const $target = $(event.target)
      const moduleId = $target.closest('.context_module').data('module-id')?.toString()
      const data = $target.data('externalTools')
      const returnFocusTo = $(`#context_module_${moduleId} .al-trigger`)[0]
      renderExternalAppsTray(true, data, moduleId, returnFocusTo)
    })
  }

  $(document).on('click', '.module_send_to', event => {
    event.preventDefault()
    const moduleId = $(event.target).closest('.context_module').data('module-id').toString()
    const selection = {content_type: 'module', content_id: moduleId}
    const returnFocusTo = $(event.target).closest('ul').prev('.al-trigger')
    renderSendToTray(true, selection, returnFocusTo)
  })

  $(document).on('click', '.assign_module_link, .view_assign_link', async function (event) {
    event.preventDefault()
    const returnFocusTo = $(event.target).closest('ul').prev('.al-trigger')
    const moduleElement = $(event.target).parents('.context_module')[0]
    const settingsProps = await parseModule(moduleElement)
    renderDifferentiatedModulesTray(returnFocusTo, moduleElement, settingsProps, {
      initialTab: 'assign-to',
    })
  })

  $(document).on('click', '.edit_module_link', async function (event) {
    event.preventDefault()
    const returnFocusTo = $(event.target).closest('ul').prev('.al-trigger')
    const moduleElement = $(event.target).parents('.context_module')[0]
    const settingsProps = await parseModule(moduleElement)
    renderDifferentiatedModulesTray(returnFocusTo, moduleElement, settingsProps, {
      initialTab: 'settings',
    })
  })

  $(document).on('click', '.module_item_copy_to', event => {
    event.preventDefault()
    const select_id = $(event.target).data('select-id')
    const select_class = $(event.target).data('select-class')
    const selection = {[select_class]: [select_id]}
    const returnFocusTo = $(event.target).closest('ul').prev('.al-trigger')
    renderCopyToTray(true, selection, returnFocusTo)
  })

  $(document).on('click', '.module_item_send_to', event => {
    event.preventDefault()
    const content_id = $(event.target).data('content-id')
    const content_type = $(event.target).data('content-type')
    const selection = {content_id, content_type}
    const returnFocusTo = $(event.target).closest('ul').prev('.al-trigger')
    renderSendToTray(true, selection, returnFocusTo)
  })

  $(document).on('click keyclick', '.module-item-assign-to-link', function (event) {
    event.preventDefault()
    const returnFocusTo = $(event.target).closest('ul').prev('.al-trigger')
    const moduleItemId = event.target.getAttribute('data-item-id')
    const moduleItemName = event.target.getAttribute('data-item-name')
    const moduleItemType = event.target.getAttribute('data-item-type')
    const courseId = event.target.getAttribute('data-item-context-id')
    const moduleItemContentId = event.target.getAttribute('data-item-content-id')
    const moduleItemHasAssignment = event.target.getAttribute('data-item-has-assignment')
    const moduleItemHasCheckpoint = event.target.getAttribute('data-item-has-assignment-checkpoint')

    const itemProps = parseModuleItemElement(
      document.getElementById(`context_module_item_${moduleItemId}`),
    )
    renderItemAssignToTray(true, returnFocusTo, {
      courseId,
      moduleItemName,
      moduleItemType,
      moduleItemContentId,
      moduleItemHasAssignment,
      moduleItemHasCheckpoint,
      ...itemProps,
    })
  })

  if (ENV.MODULE_FEATURES?.TEACHER_MODULE_SELECTION) {
    $('#show_teacher_only_module_id').on('change', () => {
      doFetchApi({
        path: `/api/v1/courses/${ENV.COURSE_ID}/settings`,
        method: 'PUT',
        body: {show_teacher_only_module_id: $('#show_teacher_only_module_id').val()},
      })
        .then(_ => {
          window.location.reload()
        })
        .catch(err => {
          showFlashError(I18n.t('Cannot set the teacher view module'))(err)
        })
    })
  }

  if (ENV.MODULE_FEATURES?.STUDENT_MODULE_SELECTION) {
    $('#show_student_only_module_id').on('change', () => {
      doFetchApi({
        path: `/api/v1/courses/${ENV.COURSE_ID}/settings`,
        method: 'PUT',
        body: {show_student_only_module_id: $('#show_student_only_module_id').val()},
      }).catch(err => {
        showFlashError(I18n.t('Cannot set the student view module'))(err)
      })
    })
  }
}

$(() => {
  const allModules = Array.from(document.querySelectorAll('.context_module'))
    .map(m => parseInt(m.dataset.moduleId, 10))
    .filter(mid => !isNaN(mid))

  if (ENV.FEATURE_MODULES_PERF) {
    // ENV.COLLAPSED_MODULES are those that have been collapsed by the user
    // ENV.EXPANDED_MODULES are those that have been expanded by the user
    // If the user has not manually changed a module's state, it will not appear in either list
    // This implies that if both arrays are empty, the user has done nothing and we will expand the first module
    // After that, default to collapsed and expand only those in the ENV.EXPANDED_MODULES array
    // Because other places in the code rely on the values in these ENV vars, mutate them here to reflect the current state.
    if (allModules.length > 0) {
      if (ENV.MODULE_FEATURES?.TEACHER_MODULE_SELECTION) {
        const moduleId = parseInt(document.getElementById('show_teacher_only_module_id')?.value, 10)
        if (!isNaN(moduleId)) {
          if (allModules.includes(moduleId)) {
            ENV.EXPANDED_MODULES = [moduleId]
            ENV.COLLAPSED_MODULES = []
          }
        }
      }
      const isInitialState = ENV.EXPANDED_MODULES.length === 0 && ENV.COLLAPSED_MODULES.length === 0
      if (isInitialState) {
        ENV.EXPANDED_MODULES.push(allModules.shift())
        ENV.COLLAPSED_MODULES = allModules
        $.ajaxJSON(
          `/courses/${ENV.COURSE_ID}/modules/${ENV.EXPANDED_MODULES[0]}/collapse`,
          'POST',
          {collapse: 0},
        )
      } else {
        ENV.COLLAPSED_MODULES = allModules.filter(mid => !ENV.EXPANDED_MODULES.includes(mid))
      }

      modules.lazyLoadItems(ENV.EXPANDED_MODULES)
    }
    for (const module of allModules) {
      addShowAllOrLess(module)
    }
    // Handle Show All and Show Less events
    // I don't bother with removeEventListener because the events are
    // bound to the document and will be dealt with on page unload
    document.addEventListener(MODULE_EXPAND_AND_LOAD_ALL, event => {
      $(`#context_module_${event.detail.moduleId} .expand_module_link`).trigger(
        'click',
        event.detail.allPages,
      )
    })
    document.addEventListener(MODULE_LOAD_ALL, event => {
      const moduleId = event.detail.moduleId
      document
        .querySelector(`#context_module_content_${moduleId} ul.context_module_items`)
        ?.replaceChildren()
      modules.lazyLoadItems([moduleId], true)
    })
    document.addEventListener(MODULE_LOAD_FIRST_PAGE, event => {
      // TODO: rather than re-querying, maybe delete all items
      //       beyond the first page and trigger
      //       re-render of ModuleItemPaging
      //       (but this is easier)
      const moduleId = event.detail.moduleId
      document
        .querySelector(`#context_module_content_${moduleId} ul.context_module_items`)
        ?.replaceChildren()
      modules.lazyLoadItems([moduleId], false)
    })
  } else {
    if ($('#context_modules').hasClass('editable')) {
      for (const moduleId of allModules) {
        initContextModuleItems(moduleId)
      }
      modules.loadMasterCourseData()
    }
  }
  initContextModules()
})

export default modules
