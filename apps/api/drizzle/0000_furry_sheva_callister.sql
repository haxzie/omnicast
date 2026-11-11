CREATE TABLE `devices` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`platform` text DEFAULT 'macos' NOT NULL,
	`app_version` text NOT NULL,
	`last_seen_at` integer NOT NULL,
	`created_at` integer DEFAULT (unixepoch() * 1000) NOT NULL
);
--> statement-breakpoint
CREATE TABLE `dictations` (
	`id` text PRIMARY KEY NOT NULL,
	`device_id` text,
	`text` text NOT NULL,
	`duration_ms` integer NOT NULL,
	`transcribe_ms` integer DEFAULT 0 NOT NULL,
	`model_id` text NOT NULL,
	`app_bundle_id` text,
	`app_name` text,
	`language` text,
	`word_count` integer DEFAULT 0 NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `dictations_created_at_idx` ON `dictations` (`created_at`);--> statement-breakpoint
CREATE INDEX `dictations_device_idx` ON `dictations` (`device_id`,`created_at`);