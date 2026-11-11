import type { NextConfig } from "next";

const config: NextConfig = {
  transpilePackages: ["@omnicast/shared"],
  typedRoutes: true,
};

export default config;
