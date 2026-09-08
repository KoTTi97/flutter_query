// Skeletons are for the *first* load only — the state where there is genuinely
// nothing to show. Every later fetch keeps the previous data on screen and
// signals itself with the small non-blocking indicator instead, because
// replacing a rendered list with grey boxes to fetch data you already have is a
// downgrade, not a loading state.
//
// The shapes mirror the real row's geometry so nothing shifts when data lands.

import { Skeleton } from '@/components/ui/skeleton'

export function SensorRowSkeleton() {
  return (
    <div aria-hidden="true" className="flex items-center gap-3 rounded-xl border bg-card p-3.5">
      <Skeleton className="size-9 rounded-lg" />
      <div className="flex-1 space-y-2">
        <Skeleton className="h-3.5 w-2/5" />
        <Skeleton className="h-3 w-3/5" />
      </div>
      <Skeleton className="h-5 w-16 rounded-full" />
    </div>
  )
}

export function SensorListSkeleton({ rows = 4 }: { rows?: number }) {
  return (
    <div aria-label="Sensoren werden geladen" className="flex flex-col gap-2" role="status">
      {Array.from({ length: rows }, (_, index) => (
        // biome-ignore lint/suspicious/noArrayIndexKey: placeholder rows have no identity
        <SensorRowSkeleton key={index} />
      ))}
    </div>
  )
}

export function SensorDetailSkeleton() {
  return (
    <div aria-label="Sensor wird geladen" className="space-y-3" role="status">
      <Skeleton className="h-7 w-2/5" />
      <Skeleton className="h-4 w-1/4" />
      <Skeleton className="h-28 w-full rounded-xl" />
      <Skeleton className="h-28 w-full rounded-xl" />
    </div>
  )
}
