import { ArrowLeft } from 'lucide-react'
import { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardAction, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { SENSOR_ICONS, SENSOR_TYPE_LABELS } from '../labels.ts'
import {
  displayedMatterForwarding,
  useRenameSensor,
  useSensor,
  useSetMatterForwarding,
} from '../queries.ts'
import { useAppStore } from '../store.ts'
import { SensorDetailSkeleton } from './Skeletons.tsx'

type RenameForm = { name: string }

export default function SensorDetail({ id }: { id: string }) {
  const closeSensor = useAppStore((state) => state.closeSensor)
  const { data: sensor, isPending, isFetching, error } = useSensor(id)
  const rename = useRenameSensor()
  const setMatterForwarding = useSetMatterForwarding()

  const { register, handleSubmit, reset, formState } = useForm<RenameForm>({
    values: { name: sensor?.name ?? '' },
  })

  // Clear a failed submit's error state once the user edits again. `reset` is
  // stable across renders, so listing it does not re-run this.
  const resetRename = rename.reset
  useEffect(() => {
    if (formState.isDirty) resetRename()
  }, [formState.isDirty, resetRename])

  const backLink = (
    <Button className="mb-4 -ml-2.5" onClick={closeSensor} size="sm" variant="ghost">
      <ArrowLeft />
      Alle Sensoren
    </Button>
  )

  // In practice this is almost never seen: opening a sensor from the overview
  // renders from the cache the list already seeded. It shows up when a detail
  // link is the first thing loaded.
  if (isPending) {
    return (
      <>
        {backLink}
        <SensorDetailSkeleton />
      </>
    )
  }
  if (error) {
    return (
      <>
        {backLink}
        <Alert variant="destructive">
          <AlertDescription>{error.message}</AlertDescription>
        </Alert>
      </>
    )
  }
  if (!sensor) return null

  const Icon = SENSOR_ICONS[sensor.type]
  const matterOn = displayedMatterForwarding(sensor)
  const settling = sensor.matterForwardingPending || setMatterForwarding.isPending

  const onSubmit = ({ name }: RenameForm) =>
    rename.mutate({ id, name }, { onSuccess: () => reset({ name }) })

  return (
    <>
      {backLink}

      <div className="mb-4">
        <h1 className="flex items-center gap-2.5 font-semibold text-2xl tracking-tight">
          <span className="grid size-9 place-items-center rounded-lg bg-muted text-muted-foreground">
            <Icon aria-hidden="true" className="size-4.5" />
          </span>
          {sensor.name}
        </h1>
        <div className="mt-1.5 flex items-center gap-2 text-muted-foreground text-xs">
          <span>
            {SENSOR_TYPE_LABELS[sensor.type]} · {sensor.room} · {sensor.temperature} °C
          </span>
          {sensor.connected ? (
            <Badge className="border-transparent bg-emerald-500/12 text-emerald-700 dark:text-emerald-400">
              verbunden
            </Badge>
          ) : (
            <Badge variant="outline">offline</Badge>
          )}
          {isFetching && <span>· wird aktualisiert</span>}
        </div>
      </div>

      <Alert className="mb-4">
        <AlertDescription>
          Diese Seite und die Zeile in der Übersicht lesen dieselbe Sensor-Query. Ein Umbenennen
          invalidiert genau einen Key, beide Ansichten aktualisieren sich aus einem einzigen
          Nachladen — ohne Abgleich zwischen Caches und ohne Reload-Verdrahtung.
        </AlertDescription>
      </Alert>

      <Card className="mb-3">
        <CardContent>
          <form onSubmit={handleSubmit(onSubmit)}>
            <Label className="mb-2" htmlFor="name">
              Sensorname
            </Label>
            <div className="flex gap-2">
              <Input id="name" {...register('name', { required: 'Name ist erforderlich' })} />
              <Button disabled={rename.isPending} type="submit">
                {rename.isPending ? 'Wird gespeichert…' : 'Speichern'}
              </Button>
            </div>
            <p className="mt-2 text-muted-foreground text-xs">
              „fail“ als Name lässt das Gateway den Schreibvorgang ablehnen. Beim Löschen schlägt
              jeder zweite Versuch fehl — damit ist auch dort das Rollback sichtbar.
            </p>
            {formState.errors.name && (
              <p className="mt-2 text-destructive text-xs">{formState.errors.name.message}</p>
            )}
            {rename.isError && (
              <p className="mt-2 text-destructive text-xs">
                {rename.error.message} — der Name wurde automatisch zurückgesetzt.
              </p>
            )}
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Matter-Weiterleitung</CardTitle>
          <CardAction className="flex items-center gap-2">
            {settling ? (
              <Badge className="border-transparent bg-amber-500/12 text-amber-700 dark:text-amber-400">
                <span className="size-1.5 animate-pulse rounded-full bg-current" />
                wird bestätigt…
              </Badge>
            ) : (
              <Badge variant={matterOn ? 'secondary' : 'outline'}>{matterOn ? 'an' : 'aus'}</Badge>
            )}
            <Switch
              aria-label="Matter-Weiterleitung umschalten"
              checked={matterOn}
              disabled={settling}
              onCheckedChange={(value) => setMatterForwarding.mutate({ id, value })}
            />
          </CardAction>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground text-xs">
            Das Gateway nimmt diesen Schreibvorgang sofort an, das Gerät bestätigt ihn aber erst
            rund 3 Sekunden später. Der Schalter springt optimistisch um und die Query pollt, bis
            das Gerät bestätigt hat.
          </p>
        </CardContent>
      </Card>
    </>
  )
}
