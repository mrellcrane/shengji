// Cloudflare Worker entry point: wires the Anthropic SDK and the Worker bindings into the handler.

import Anthropic from "@anthropic-ai/sdk";
import { handleCoach } from "./handler.ts";
import type { UpstreamStream, UpstreamText } from "./handler.ts";
import type { ApiMessage } from "./protocol.ts";
import { SYSTEM_PROMPT } from "./prompt.ts";

interface CoachEnv extends Env {
  /** Worker secret, set by the deploy workflow. */
  ANTHROPIC_API_KEY?: string;
}

/** Room for a little adaptive thinking plus a short answer. */
const MAX_TOKENS = 2048;

function startStream(client: Anthropic, model: string, messages: ApiMessage[]): UpstreamStream {
  const stream = client.messages.stream({
    model,
    max_tokens: MAX_TOKENS,
    // Chat-style coaching: low effort keeps replies fast and cheap; thinking stays adaptive.
    output_config: { effort: "low" },
    system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
    messages,
  });

  async function* events(): AsyncGenerator<UpstreamText> {
    for await (const event of stream) {
      if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
        yield { type: "text", text: event.delta.text };
      }
    }
  }

  return {
    events: events(),
    finish: async () => {
      const message = await stream.finalMessage();
      return { stopReason: message.stop_reason };
    },
    abort: () => stream.abort(),
  };
}

function describeError(error: unknown): { code: string; message: string } {
  if (error instanceof Anthropic.RateLimitError) {
    return { code: "busy", message: "The coach is busy right now. Try again in a minute." };
  }
  if (error instanceof Anthropic.AuthenticationError || error instanceof Anthropic.PermissionDeniedError) {
    return { code: "not_configured", message: "The coach isn't set up correctly yet." };
  }
  if (error instanceof Anthropic.BadRequestError) {
    return { code: "bad_request", message: "The coach couldn't answer that. Try rephrasing, or start a new chat." };
  }
  if (error instanceof Anthropic.APIConnectionError) {
    return { code: "unavailable", message: "The coach can't be reached right now. Try again in a minute." };
  }
  if (error instanceof Anthropic.APIError) {
    return { code: "unavailable", message: "The coach is unavailable right now. Try again in a minute." };
  }
  return { code: "unavailable", message: "Something went wrong with the coach. Try again in a minute." };
}

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return Response.json({ ok: true, model: env.MODEL, keyConfigured: Boolean(env.ANTHROPIC_API_KEY) });
    }
    if (url.pathname !== "/coach") {
      return Response.json({ error: "not_found" }, { status: 404 });
    }
    if (!env.ANTHROPIC_API_KEY) {
      return Response.json({ error: "not_configured", message: "The coach isn't set up yet." }, { status: 503 });
    }

    const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 1 });
    return handleCoach(request, {
      deviceLimiter: env.DEVICE_LIMITER,
      ipLimiter: env.IP_LIMITER,
      startStream: (messages) => startStream(client, env.MODEL, messages),
      describeError,
      log: (message) => console.error(message),
      waitUntil: (promise) => ctx.waitUntil(promise),
    });
  },
} satisfies ExportedHandler<CoachEnv>;
