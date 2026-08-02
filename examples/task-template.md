---
title: "Example: Add user profile page"
app: my-app
repo: /home/dev/my-app
branch: feature/user-profile
max_budget_usd: 5.00
max_hours: 4
verification: full
---

# Task: Add User Profile Page

## Phase 1: Database and API

Create the database schema for user profiles and the API endpoints.

- Add `user_profiles` table with fields: id, user_id, bio, avatar_url, created_at
- Create GET /api/profiles/:id endpoint
- Create PUT /api/profiles/:id endpoint
- Add RLS policies for the new table

## Phase 2: Frontend Components

Build the React components for the profile page.

- Create ProfilePage component with avatar, bio, and edit functionality
- Create ProfileEditForm component
- Add profile route to the app router
- Style with existing design system

## Phase 3: Integration and Polish

Connect everything and add final touches.

- Wire up frontend to API endpoints
- Add loading and error states
- Add form validation
- Test the full flow end-to-end
