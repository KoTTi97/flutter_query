import AppHeader from './components/AppHeader.tsx'
import SensorDetail from './components/SensorDetail.tsx'
import SensorOverview from './components/SensorOverview.tsx'
import { useAppStore } from './store.ts'

export default function App() {
  // Which screen is open is client state, so it lives in zustand — not in the
  // query cache, and not in a useState that the header would then need threaded
  // down to it.
  const openSensorId = useAppStore((state) => state.openSensorId)

  return (
    <>
      <AppHeader />
      <main className="mx-auto max-w-3xl px-6 pt-8 pb-20">
        {openSensorId ? (
          <SensorDetail id={openSensorId} />
        ) : (
          <>
            <h1 className="font-semibold text-3xl tracking-tight">Sensoren</h1>
            <p className="mt-1.5 mb-7 text-muted-foreground text-sm">
              TanStack-Query-Referenz für den Umbau der Sensor-Domäne. Das Dummy-Gateway ist
              absichtlich langsam — rund 900 ms pro Listenabruf und 700 ms pro Schreibvorgang.
            </p>

            <SensorOverview />
          </>
        )}
      </main>
    </>
  )
}
