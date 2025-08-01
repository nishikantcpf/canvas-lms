/*
 * Copyright (C) 2025 - present Instructure, Inc.
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

import React from 'react'
import {render, screen, fireEvent} from '@testing-library/react'
import '@testing-library/jest-dom/extend-expect'
import TranslationControls from '../TranslationControls'
import {TranslationContext, TranslationContextValue} from '../../../hooks/useTranslationContext'

describe('TranslationControls', () => {
  const defaultProps = {
    inboxSettingsFeature: false,
    signature: '',
  }

  it('renders without crashing', () => {
    render(
      <TranslationContext.Provider value={{body: ''} as TranslationContextValue}>
        <TranslationControls signature="" inboxSettingsFeature={false} />
      </TranslationContext.Provider>,
    )
    expect(screen.getByText(/Include translated version of this message/i)).toBeInTheDocument()
  })

  it('toggles the checkbox', () => {
    render(
      <TranslationContext.Provider value={{body: ''} as TranslationContextValue}>
        <TranslationControls {...defaultProps} />
      </TranslationContext.Provider>,
    )
    const checkbox = screen.getByLabelText('Include translated version of this message')
    expect(checkbox).not.toBeChecked()
    fireEvent.click(checkbox)
    expect(checkbox).toBeChecked()
  })

  it('displays TranslationOptions when checkbox is checked', () => {
    render(
      <TranslationContext.Provider value={{body: ''} as TranslationContextValue}>
        <TranslationControls {...defaultProps} />
      </TranslationContext.Provider>,
    )
    const checkbox = screen.getByLabelText('Include translated version of this message')
    fireEvent.click(checkbox)
    expect(screen.getByText(/Translate To/i)).toBeInTheDocument()
  })
})
