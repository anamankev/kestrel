/// <reference types="@cloudflare/workers-types" />
import { handle, type Env } from "./relay";

export default {
  fetch(req: Request, env: Env): Promise<Response> {
    return handle(req, env, (u, i) => fetch(u, i), caches.default);
  },
};
