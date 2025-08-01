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

import {act, render, within} from '@testing-library/react'
import {renderConnected} from '../../__tests__/utils'
import fakeENV from '@canvas/test-utils/fakeENV'

import {Footer, type ComponentProps} from '../footer'

const syncUnpublishedChanges = jest.fn()
const onResetPace = jest.fn()
const removePace = jest.fn()
const handleCancel = jest.fn()

const defaultProps: ComponentProps = {
  autoSaving: false,
  pacePublishing: false,
  isSyncing: false,
  syncUnpublishedChanges,
  onResetPace,
  showLoadingOverlay: false,
  studentPace: false,
  sectionPace: false,
  unpublishedChanges: true,
  newPace: false,
  removePace,
  blackoutDatesUnsynced: false,
  blackoutDatesSyncing: false,
  handleCancel,
  responsiveSize: 'large' as const,
  anyActiveRequests: false,
  isUnpublishedNewPace: false,
  paceName: 'Cool Class',
  isSavingDraft: false,
  blueprintLocked: false,
  isDraftPace: false,
  isBulkEnrollment: false,
}

describe('Footer', () => {
  afterEach(() => {
    fakeENV.teardown()
    jest.clearAllMocks()
  })

  it('renders apply changes buttons when there are unpublished changes', () => {
    const {getByRole} = renderConnected(<Footer {...defaultProps} />)
    const publishButton = getByRole('button', {name: 'Apply Changes'})
    expect(publishButton).toBeInTheDocument()
    act(() => publishButton.click())
    expect(syncUnpublishedChanges).toHaveBeenCalled()
  })

  it('shows apply changes tooltip when there are no unpublished changes', () => {
    const {getByRole} = renderConnected(<Footer {...defaultProps} unpublishedChanges={false} />)
    const publishButton = getByRole('button', {name: 'Apply Changes'})
    expect(publishButton).toHaveAttribute('aria-describedby')
  })

  it('shows apply changestooltip while publishing', () => {
    const {getByRole} = renderConnected(
      <Footer {...defaultProps} pacePublishing={true} isSyncing={true} />,
    )
    const publishButton = getByRole('button', {name: 'Publishing...'})
    expect(publishButton).toHaveAttribute('aria-describedby')
  })

  it('shows apply changes tooltip while auto saving', () => {
    const {getByRole} = renderConnected(<Footer {...defaultProps} autoSaving={true} />)
    const publishButton = getByRole('button', {name: 'Apply Changes'})
    expect(publishButton).toHaveAttribute('aria-describedby')
  })

  it('shows cannot cancel and publish tooltip while loading', () => {
    const {getByText} = renderConnected(
      <Footer {...defaultProps} showLoadingOverlay={true} anyActiveRequests={true} />,
    )
    expect(getByText('You cannot cancel while loading the pace')).toBeInTheDocument()
    expect(getByText('You cannot publish while loading the pace')).toBeInTheDocument()
  })

  it('shows cannot cancel when a new pace', () => {
    const {getByText, queryByText} = renderConnected(
      <Footer {...defaultProps} unpublishedChanges={false} newPace={true} />,
    )
    expect(queryByText('You cannot publish while loading the pace')).not.toBeInTheDocument()
  })

  it('renders a loading spinner inside the publish button when publishing is ongoing', () => {
    const {getByRole} = renderConnected(
      <Footer {...defaultProps} pacePublishing={true} isSyncing={true} />,
    )

    const publishButton = getByRole('button', {name: 'Publishing...'})
    expect(publishButton).toBeInTheDocument()

    const spinner = within(publishButton).getByRole('img', {name: 'Publishing...'})
    expect(spinner).toBeInTheDocument()
  })

  it('keeps focus on Publish button after clicking', () => {
    const {getByRole} = renderConnected(<Footer {...defaultProps} />)

    const pubButton = getByRole('button', {name: 'Apply Changes'})
    act(() => {
      pubButton.focus()
      pubButton.click()
    })
    expect(document.activeElement).toBe(pubButton)
  })

  describe('with course paces for students', () => {
    it('renders everything for student paces', () => {
      const {getByRole} = renderConnected(<Footer {...defaultProps} studentPace={true} />)
      const publishButton = getByRole('button', {name: 'Apply Changes'})
      expect(publishButton).toBeInTheDocument()
      act(() => publishButton.click())
      expect(syncUnpublishedChanges).toHaveBeenCalled()
    })
  })

  describe('with course_paces_redesign flag', () => {
    it('includes the correct components for new pace', () => {
      const {getByText, queryByText} = renderConnected(
        <Footer {...defaultProps} sectionPace={true} newPace={true} isUnpublishedNewPace={true} />,
      )
      const closeButton = getByText('Close').closest('button')
      expect(closeButton).toBeInTheDocument()
      expect(closeButton).toBeEnabled()
      const createButton = getByText('Create Pace').closest('button')
      expect(createButton).toBeInTheDocument()
      expect(createButton).toBeEnabled()
      expect(queryByText('Remove Pace')).not.toBeInTheDocument()
      expect(getByText('Pace is new and unpublished')).toBeInTheDocument()
    })

    it('includes the correct components for publishing new pace', () => {
      const {getByText, queryByText, getByTitle} = renderConnected(
        <Footer
          {...defaultProps}
          sectionPace={true}
          isUnpublishedNewPace={true}
          anyActiveRequests={true}
          isSyncing={true}
        />,
      )
      const closeButton = getByText('Close').closest('button')
      expect(closeButton).toBeInTheDocument()
      expect(closeButton).toBeDisabled()
      const createButton = getByTitle('Publishing...').closest('button')
      expect(createButton).toBeInTheDocument()
      expect(createButton).toBeDisabled()
      expect(queryByText('Remove Pace')).not.toBeInTheDocument()
      expect(getByText('Publishing...')).toBeInTheDocument()
    })

    it('includes the correct components for an existing, unchanged pace', () => {
      const {getByText} = renderConnected(
        <Footer {...defaultProps} sectionPace={true} unpublishedChanges={false} />,
      )
      const closeButton = getByText('Close').closest('button')
      expect(closeButton).toBeInTheDocument()
      expect(closeButton).toBeEnabled()
      const createButton = getByText('Apply Changes').closest('button')
      expect(createButton).toBeInTheDocument()
      expect(createButton).toBeDisabled()
      const removeButton = getByText('Remove Pace').closest('button')
      expect(removeButton).toBeInTheDocument()
      expect(removeButton).toBeEnabled()
      expect(getByText('No pending changes')).toBeInTheDocument()
    })

    it('includes the correct components for an existing, changed pace', () => {
      const {getByText} = renderConnected(<Footer {...defaultProps} sectionPace={true} />)
      const closeButton = getByText('Close').closest('button')
      expect(closeButton).toBeInTheDocument()
      expect(closeButton).toBeEnabled()
      const createButton = getByText('Apply Changes').closest('button')
      expect(createButton).toBeInTheDocument()
      expect(createButton).toBeEnabled()
      const removeButton = getByText('Remove Pace').closest('button')
      expect(removeButton).toBeInTheDocument()
      expect(removeButton).toBeEnabled()
    })

    it('includes the correct components for publishing existing pace while creating job', () => {
      const {getByText, getByTitle} = renderConnected(
        <Footer
          {...defaultProps}
          sectionPace={true}
          isSyncing={true}
          pacePublishing={true}
          anyActiveRequests={true}
        />,
      )
      const closeButton = getByText('Close').closest('button')
      expect(closeButton).toBeInTheDocument()
      expect(closeButton).toBeDisabled()
      const createButton = getByTitle('Publishing...').closest('button')
      expect(createButton).toBeInTheDocument()
      expect(createButton).toBeDisabled()
      const removeButton = getByText('Remove Pace').closest('button')
      expect(removeButton).toBeInTheDocument()
      expect(removeButton).toBeDisabled()
      expect(getByText('Publishing...')).toBeInTheDocument()
    })

    it('includes the correct components for publishing existing pace after job creation', () => {
      const {getByText, getByTitle} = renderConnected(
        <Footer
          {...defaultProps}
          sectionPace={true}
          isSyncing={true}
          pacePublishing={true}
          anyActiveRequests={false}
        />,
      )
      const closeButton = getByText('Close').closest('button')
      expect(closeButton).toBeInTheDocument()
      expect(closeButton).toBeEnabled()
      const createButton = getByTitle('Publishing...').closest('button')
      expect(createButton).toBeInTheDocument()
      expect(createButton).toBeDisabled()
      const removeButton = getByText('Remove Pace').closest('button')
      expect(removeButton).toBeInTheDocument()
      expect(removeButton).toBeDisabled()
      expect(getByText('Publishing...')).toBeInTheDocument()
    })

    describe('Remove Pace button', () => {
      it('renders a button for existing section pace types', () => {
        const {getByText} = renderConnected(<Footer {...defaultProps} sectionPace={true} />)
        expect(getByText('Remove Pace', {selector: 'button span'})).toBeInTheDocument()
      })

      it('does not render a button for existing course pace types', () => {
        const {getByText, queryByText} = renderConnected(<Footer {...defaultProps} />)
        expect(getByText('No pending changes')).toBeInTheDocument()
        expect(queryByText('Remove Pace', {selector: 'button span'})).not.toBeInTheDocument()
      })

      it('does not render a button for new section paces', () => {
        const {getByText, queryByText} = renderConnected(
          <Footer {...defaultProps} sectionPace={true} newPace={true} />,
        )
        expect(getByText('Pace is new and unpublished')).toBeInTheDocument()
        expect(queryByText('Remove Pace', {selector: 'button span'})).not.toBeInTheDocument()
      })

      it('opens a confirmation modal on click', () => {
        const {getByText} = renderConnected(<Footer {...defaultProps} sectionPace={true} />)
        const removeButton = getByText('Remove Pace', {selector: 'button span'})
        act(() => removeButton.click())
        expect(getByText('Remove this Section Pace?')).toBeInTheDocument()
        expect(
          getByText(
            'Cool Class Pace will be removed. This pace will revert back to the default pace.',
          ),
        ).toBeInTheDocument()
      })

      it('closes modal when close button is clicked', () => {
        const {getByText, getAllByText} = renderConnected(
          <Footer {...defaultProps} sectionPace={true} />,
        )
        const removeButton = getByText('Remove Pace', {selector: 'button span'})
        act(() => removeButton.click())
        const cancelButton = getAllByText('Close', {selector: 'button span'})[1]
        expect(cancelButton).toBeInTheDocument()
        act(() => cancelButton.click())
        expect(removePace).not.toHaveBeenCalled()
      })

      it('calls removePace when confirmed in modal', () => {
        const {getByText} = renderConnected(<Footer {...defaultProps} sectionPace={true} />)
        const removeButton = getByText('Remove Pace', {selector: 'button span'})
        act(() => removeButton.click())
        const confirmButton = getByText('Remove', {selector: 'button span'})
        expect(confirmButton).toBeInTheDocument()
        expect(removePace).not.toHaveBeenCalled()
        act(() => confirmButton.click())
        expect(removePace).toHaveBeenCalledTimes(1)
      })
    })

    it('calls focusOnClose when publish button is clicked', () => {
      const focusOnClose = jest.fn()
      const {getByRole} = renderConnected(<Footer {...defaultProps} focusOnClose={focusOnClose} />)
      const publishButton = getByRole('button', {name: 'Apply Changes'})
      act(() => publishButton.click())
      expect(focusOnClose).toHaveBeenCalledTimes(1)
    })
  })
})
