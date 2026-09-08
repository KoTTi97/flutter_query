import { useEffect, useState } from 'react'

/**
 * Holds a value still for `delay` ms.
 *
 * Used on the search box: the typed value drives the input, the debounced value
 * drives the query key. Without this, every keystroke is a new key and so a new
 * list request — typing "schlafzimmer" would queue thirteen of them, which is
 * precisely the request storm the real gateway cannot survive.
 */
export function useDebouncedValue<T>(value: T, delay = 300): T {
  const [debounced, setDebounced] = useState(value)

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay)
    return () => clearTimeout(timer)
  }, [value, delay])

  return debounced
}
