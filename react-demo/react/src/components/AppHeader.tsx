// The point of this component: it is a sibling of the overview, mounted at a
// completely different place in the tree, and it gets the sensor list by simply
// asking for it. No prop drilling, no lifted state, no context of its own, and —
// because it resolves to the same query key as the unfiltered overview list — no
// second request. Delete the overview and this still works; mount five more
// copies and there is still one fetch.

import { useIsFetching } from '@tanstack/react-query'
import { ChevronDown, LoaderCircle } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Skeleton } from '@/components/ui/skeleton'
import { cn } from '@/lib/utils'
import { SENSOR_ICONS, SENSOR_TYPE_LABELS } from '../labels.ts'
import { useConnectedSensors } from '../queries.ts'
import { useAppStore } from '../store.ts'

export default function AppHeader() {
  const { data } = useConnectedSensors()

  // Also reused freely: a global "something is in flight" signal that no
  // component had to be told about.
  const fetching = useIsFetching()

  // The menu is still driven by the store, but Radix owns the outside-click and
  // Escape handling now — that is a whole effect this component used to carry.
  const menuOpen = useAppStore((state) => state.sensorMenuOpen)
  const setMenuOpen = useAppStore((state) => state.setSensorMenuOpen)
  const openSensor = useAppStore((state) => state.openSensor)

  return (
    <header className="sticky top-0 z-20 border-b bg-background/85 backdrop-blur-md backdrop-saturate-150">
      <div className="mx-auto flex h-14 max-w-3xl items-center justify-between gap-3 px-6">
        <div className="flex min-w-0 items-center gap-2">
          <span className="text-primary">◈</span>
          <span className="font-semibold tracking-tight">Sensor-Gateway</span>
        </div>

        <div className="flex items-center gap-2">
          {/* Non-blocking: it appears next to the content instead of replacing it. */}
          <span
            className={cn(
              'flex items-center gap-1.5 text-muted-foreground text-xs transition-opacity duration-200',
              fetching > 0 ? 'opacity-100' : 'opacity-0',
            )}
          >
            <LoaderCircle aria-hidden="true" className="size-3 animate-spin" />
            Wird aktualisiert…
          </span>

          <DropdownMenu onOpenChange={setMenuOpen} open={menuOpen}>
            <DropdownMenuTrigger asChild>
              <Button className="rounded-full" disabled={!data} size="sm" variant="outline">
                <span
                  className={cn(
                    'size-1.5 rounded-full',
                    data ? 'bg-emerald-500 ring-3 ring-emerald-500/20' : 'bg-muted-foreground',
                  )}
                />
                {data ? (
                  <span>
                    {data.connected.length} von {data.total} verbunden
                  </span>
                ) : (
                  <Skeleton className="h-3 w-24" />
                )}
                <ChevronDown aria-hidden="true" className="text-muted-foreground" />
              </Button>
            </DropdownMenuTrigger>

            <DropdownMenuContent align="end" className="w-64">
              <DropdownMenuLabel>Verbundene Sensoren</DropdownMenuLabel>
              {data?.connected.map((sensor) => {
                const Icon = SENSOR_ICONS[sensor.type]
                return (
                  <DropdownMenuItem
                    className="gap-2.5"
                    key={sensor.id}
                    onSelect={() => openSensor(sensor.id)}
                  >
                    <span className="grid size-7 shrink-0 place-items-center rounded-md bg-muted">
                      <Icon aria-hidden="true" className="size-3.5" />
                    </span>
                    <span className="flex min-w-0 flex-col">
                      <span className="truncate font-medium">{sensor.name}</span>
                      <span className="text-muted-foreground text-xs">
                        {SENSOR_TYPE_LABELS[sensor.type]} · {sensor.room}
                      </span>
                    </span>
                  </DropdownMenuItem>
                )
              })}
              {data?.connected.length === 0 && (
                <p className="px-2 py-1.5 text-muted-foreground text-xs">Kein Sensor verbunden.</p>
              )}
              {data && data.total > data.connected.length && (
                <>
                  <DropdownMenuSeparator />
                  <p className="px-2 py-1.5 text-muted-foreground text-xs">
                    {data.total - data.connected.length} nicht erreichbar
                  </p>
                </>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>
    </header>
  )
}
