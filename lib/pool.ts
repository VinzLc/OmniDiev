/** Exécute `work` sur chaque élément, `size` tâches en vol au maximum. */
export async function pool<T, R>(
  items: T[],
  size: number,
  work: (item: T, index: number) => Promise<R>,
  onDone?: (done: number, total: number) => void,
): Promise<R[]> {
  const out = new Array<R>(items.length);
  let next = 0;
  let done = 0;

  const runner = async () => {
    for (;;) {
      const i = next++;
      if (i >= items.length) return;
      out[i] = await work(items[i], i);
      onDone?.(++done, items.length);
    }
  };

  await Promise.all(Array.from({ length: Math.min(size, items.length) }, runner));
  return out;
}
