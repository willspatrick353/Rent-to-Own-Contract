/// <reference types="vitest" />
import { defineConfig } from "vite";

export default defineConfig({
  test: {
    environment: "clarinet",
    singleThread: true,
    reporter: ["verbose"],
    environmentOptions: {
      clarinet: {
        manifestPath: "Clarinet.toml",
        coverage: false,
        costs: false,
        coverageFilename: "lcov.info",
        costsFilename: "costs-reports.json",
      },
    },
  },
});
