import { LoaderCircle, Plus, RefreshCw, Trash2 } from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { cn } from '@/lib/utils'
import { useDebouncedValue } from '../hooks/useDebouncedValue.ts'
import { ROOMS, SENSOR_ICONS, SENSOR_TYPE_LABELS } from '../labels.ts'
import {
  displayedMatterForwarding,
  useCreateSensor,
  useDeleteSensor,
  useSensor,
  useSensors,
} from '../queries.ts'
import { useAppStore } from '../store.ts'
import { SensorListSkeleton } from './Skeletons.tsx'

type SensorRowProps = {
  id: string
  onOpen: () => void
  onDelete: () => void
}

// The row subscribes to the same per-sensor query the detail screen uses, so a
// rename invalidating that one key updates this row too — no list refetch, and
// nothing to wire up between the two screens.
function SensorRow({ id, onOpen, onDelete }: SensorRowProps) {
  const { data: sensor } = useSensor(id)
  if (!sensor) return null

  const Icon = SENSOR_ICONS[sensor.type]
  const matterOn = displayedMatterForwarding(sensor)

  return (
    <div className="flex items-center gap-3 rounded-xl border bg-card p-3.5 shadow-xs transition-shadow hover:shadow-md">
      <span
        className={cn(
          'grid size-9 shrink-0 place-items-center rounded-lg bg-muted text-muted-foreground',
          !sensor.connected && 'opacity-50',
        )}
      >
        <Icon aria-hidden="true" className="size-4" />
      </span>

      <div className="min-w-0 flex-1">
        <div className={cn('truncate font-medium', !sensor.connected && 'text-muted-foreground')}>
          {sensor.name}
        </div>
        <div className="flex flex-wrap items-center gap-1.5 text-muted-foreground text-xs">
          <span>{SENSOR_TYPE_LABELS[sensor.type]}</span>
          <span aria-hidden="true">·</span>
          <span>{sensor.room}</span>
          <span aria-hidden="true">·</span>
          <span className={cn(sensor.battery < 20 && 'text-destructive')}>
            {sensor.battery} % Batterie
          </span>
        </div>
      </div>

      {!sensor.connected && <Badge variant="outline">offline</Badge>}
      {sensor.matterForwardingPending && (
        <Badge className="border-transparent bg-amber-500/12 text-amber-700 dark:text-amber-400">
          <span className="size-1.5 animate-pulse rounded-full bg-current" />
          wird bestätigt
        </Badge>
      )}
      {matterOn && !sensor.matterForwardingPending && <Badge variant="secondary">Matter</Badge>}

      <div className="flex shrink-0 items-center gap-1">
        <Button onClick={onOpen} size="sm" variant="ghost">
          Öffnen
        </Button>
        <Button
          aria-label={`${sensor.name} löschen`}
          onClick={onDelete}
          size="icon-sm"
          variant="ghost"
        >
          <Trash2 />
        </Button>
      </div>
    </div>
  )
}

export default function SensorOverview() {
  const search = useAppStore((state) => state.search)
  const setSearch = useAppStore((state) => state.setSearch)
  const room = useAppStore((state) => state.room)
  const setRoom = useAppStore((state) => state.setRoom)
  const openSensor = useAppStore((state) => state.openSensor)

  // The typed value drives the input; the settled value drives the query key.
  // One request per pause in typing instead of one per keystroke.
  const debouncedSearch = useDebouncedValue(search, 300)
  const filters = { search: debouncedSearch, room }

  const { data, isPending, isFetching, error, refetch } = useSensors(filters)
  const createSensor = useCreateSensor()
  const deleteSensor = useDeleteSensor()

  const toolbar = (
    <div className="mb-3.5 flex flex-wrap items-center gap-2">
      <Input
        className="min-w-40 flex-1"
        onChange={(event) => setSearch(event.target.value)}
        placeholder="Sensoren durchsuchen…"
        value={search}
      />
      <Select onValueChange={setRoom} value={room}>
        <SelectTrigger className="w-36">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Alle Räume</SelectItem>
          {ROOMS.map((name) => (
            <SelectItem key={name} value={name}>
              {name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <Button disabled={isFetching} onClick={() => refetch()} variant="outline">
        <RefreshCw />
        Aktualisieren
      </Button>
      <Button
        disabled={createSensor.isPending}
        onClick={() =>
          createSensor.mutate({ name: `Neuer Sensor ${Date.now() % 1000}`, room: 'Küche' })
        }
      >
        <Plus />
        {createSensor.isPending ? 'Wird hinzugefügt…' : 'Sensor hinzufügen'}
      </Button>
    </div>
  )

  // Skeletons only on the very first load, when there is nothing to show yet.
  if (isPending) {
    return (
      <>
        {toolbar}
        <p className="mb-3 text-muted-foreground text-xs">Sensoren werden geladen…</p>
        <SensorListSkeleton />
      </>
    )
  }

  if (error) {
    return (
      <>
        {toolbar}
        <Alert variant="destructive">
          <AlertDescription>{error.message}</AlertDescription>
        </Alert>
        <Button className="mt-3" onClick={() => refetch()} variant="outline">
          Erneut versuchen
        </Button>
      </>
    )
  }

  return (
    <>
      {toolbar}

      <div className="mb-3 flex items-center gap-2 text-muted-foreground text-xs">
        <span>
          {data.sensors.length} {data.sensors.length === 1 ? 'Sensor' : 'Sensoren'} · Stand{' '}
          {new Date(data.fetchedAt).toLocaleTimeString('de-DE')}
        </span>
        {/* Revalidation says so quietly and leaves the list alone. */}
        {isFetching && (
          <span className="flex items-center gap-1.5">
            <LoaderCircle aria-hidden="true" className="size-3 animate-spin" />
            wird aktualisiert
          </span>
        )}
      </div>

      {deleteSensor.isError && (
        <Alert className="mb-3" variant="destructive">
          <AlertDescription>
            {deleteSensor.error.message} — der Sensor wurde in der Liste wiederhergestellt.
          </AlertDescription>
        </Alert>
      )}

      <div className="flex flex-col gap-2">
        {data.sensors.map((sensor) => (
          <SensorRow
            id={sensor.id}
            key={sensor.id}
            onDelete={() => deleteSensor.mutate({ id: sensor.id })}
            onOpen={() => openSensor(sensor.id)}
          />
        ))}
        {data.sensors.length === 0 && (
          <p className="rounded-xl border border-dashed py-9 text-center text-muted-foreground text-sm">
            Kein Sensor passt zu diesem Filter.
          </p>
        )}
      </div>
    </>
  )
}
