/*
|--------------------------------------------------------------------------
| Environment variables service
|--------------------------------------------------------------------------
|
| The `Env.create` method creates an instance of the Env service. The
| service validates the environment variables and also cast values
| to JavaScript data types.
|
*/

import { Env } from '@adonisjs/core/env'

export default await Env.create(new URL('../', import.meta.url), {
  NODE_ENV: Env.schema.enum(['development', 'production', 'test'] as const),
  PORT: Env.schema.number(),
  APP_KEY: Env.schema.string(),
  HOST: Env.schema.string({ format: 'host' }),
  URL: Env.schema.string(),
  LOG_LEVEL: Env.schema.string(),
  INTERNET_STATUS_TEST_URL: Env.schema.string.optional(),

  /*
  |----------------------------------------------------------
  | Variables for configuring storage paths
  |----------------------------------------------------------
  */
  NOMAD_STORAGE_PATH: Env.schema.string.optional(),

  /*
  |----------------------------------------------------------
  | Variables for macOS / native Ollama support
  |----------------------------------------------------------
  | OLLAMA_HOST: Set to use a native (non-Docker) Ollama instance.
  |   e.g., "http://host.docker.internal:11434" for macOS Metal acceleration.
  | APPLE_CHIP_MODEL: Injected by the macOS install script to identify the chip
  |   (e.g., "Apple M3 Pro"). Used when si.cpu() returns empty data inside Docker.
  */
  OLLAMA_HOST: Env.schema.string.optional(),
  APPLE_CHIP_MODEL: Env.schema.string.optional(),

  /*
  |----------------------------------------------------------
  | Variables for configuring session package
  |----------------------------------------------------------
  */
  //SESSION_DRIVER: Env.schema.enum(['cookie', 'memory'] as const),

  /*
  |----------------------------------------------------------
  | Variables for configuring the database package
  |----------------------------------------------------------
  */
  DB_HOST: Env.schema.string({ format: 'host' }),
  DB_PORT: Env.schema.number(),
  DB_USER: Env.schema.string(),
  DB_PASSWORD: Env.schema.string.optional(),
  DB_DATABASE: Env.schema.string(),
  DB_SSL: Env.schema.boolean.optional(),

  /*
  |----------------------------------------------------------
  | Variables for configuring the Redis connection
  |----------------------------------------------------------
  */
  REDIS_HOST: Env.schema.string({ format: 'host' }),
  REDIS_PORT: Env.schema.number(),

  /*
  |----------------------------------------------------------
  | Variables for configuring Project Nomad's external API URL
  |----------------------------------------------------------
  */
  NOMAD_API_URL: Env.schema.string.optional(),
})
