# Parkitect

Parking lot intelligence platform powered by Next.js 15, Supabase, and PostGIS.

## Project Structure

This is a Turborepo monorepo with the following structure:

```
parkitect/
├── apps/
│   └── web/              # Next.js 15 App Router application
├── packages/
│   └── types/            # Shared TypeScript types and definitions
├── supabase/
│   └── migrations/       # Database migration files
├── turbo.json           # Turborepo configuration
└── package.json         # Root package.json
```

## Quick Start

### Prerequisites
- Node.js >= 20.0.0
- npm >= 10.2.4
- Supabase account with PostGIS extension enabled

### Development

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Type check
npm run type-check

# Lint
npm run lint

# Build
npm run build
```

## Features

- 🏗️ **Turborepo Monorepo**: Optimized build system with shared packages
- 🎨 **Next.js 15 App Router**: Latest React and Next.js with server components
- 🗺️ **Mapbox Integration**: Interactive parking lot visualization
- 🎭 **Konva Canvas**: Advanced graphics for lot feature annotation
- 💾 **Supabase**: PostgreSQL database with PostGIS spatial queries
- 🔐 **Row-Level Security**: Multi-tenant architecture with RLS
- 📦 **shadcn/ui Ready**: Pre-configured for component library
- 🌊 **TypeScript Strict Mode**: Full type safety

## Apps

### web

Next.js 15 application with:
- App Router for modern routing
- TypeScript strict mode
- Tailwind CSS for styling
- shadcn/ui components
- Mapbox GL JS for mapping
- Konva for canvas drawing

## Packages

### types

Shared TypeScript type definitions:
- `OrganizationRole`: Role-based access control
- `FeatureType`: Parking lot feature types
- `ConditionRating`: Assessment ratings
- `LotFeature`: Feature entities
- `LotRevision`: Change tracking
- And more...

## Database

PostgreSQL with PostGIS extension for spatial data:
- Organizations and multi-tenancy
- Users and membership management
- Parking lot properties and geometries
- Feature tracking and revisions
- Inspection workflows

See `supabase/migrations/` for full schema.

## License

Private
