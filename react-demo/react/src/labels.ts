// The UI is German and the strings are hardcoded — this is a reference demo, so
// an i18n layer would be noise. Room names come from the gateway already in
// German, so they are rendered as-is.

import { Activity, DoorOpen, type LucideIcon, Thermometer } from 'lucide-react'
import type { SensorType } from '../shared/types.ts'

export const SENSOR_TYPE_LABELS: Record<SensorType, string> = {
  contact: 'Kontakt',
  motion: 'Bewegung',
  temperature: 'Temperatur',
}

export const SENSOR_ICONS: Record<SensorType, LucideIcon> = {
  contact: DoorOpen,
  motion: Activity,
  temperature: Thermometer,
}

export const ROOMS = ['Küche', 'Flur', 'Wohnzimmer', 'Schlafzimmer', 'Garage']
