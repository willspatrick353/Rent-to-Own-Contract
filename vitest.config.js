/// <reference types="vitest" />
import { defineConfig } from "vite";

export default defineConfig({
  test: {
    environment: "clarinet", // Use the custom clarinet environment for Stacks
  },
});