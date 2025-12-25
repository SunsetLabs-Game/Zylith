/** @type {import('next').NextConfig} */
const nextConfig = {
  // Use webpack instead of Turbopack to avoid symlink issues
  // This can be removed once Turbopack handles symlinks better
  typescript: {
    // Exclude scripts directory from type checking during build
    ignoreBuildErrors: false,
  },
  // Exclude scripts from being processed
  pageExtensions: ['ts', 'tsx', 'js', 'jsx'],
};

export default nextConfig;

