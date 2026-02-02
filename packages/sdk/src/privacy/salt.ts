import { randomBytes } from "node:crypto";

export type Hex = `0x${string}`;

export function generateSalt(): Hex {
  return `0x${randomBytes(32).toString("hex")}` as Hex;
}
