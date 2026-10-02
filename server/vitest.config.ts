import { defineConfig } from 'vitest/config';

// Both test files share one throwaway Postgres database and each resets
// tables between tests, so test files must not run concurrently against it.
export default defineConfig({
  test: {
    fileParallelism: false,
    testTimeout: 20_000,
    hookTimeout: 20_000,
  },
});
