// Runs a read and keeps the failure, so a page can show a notice and still render the rest of
// the screen. Used instead of try/catch in each page.
export async function settle<T>(read: () => Promise<T>): Promise<{ value: T | null; error: unknown }> {
  try {
    return { value: await read(), error: null };
  } catch (error) {
    return { value: null, error };
  }
}
