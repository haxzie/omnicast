/**
 * The catalog of local speech models Omnicast can download after install.
 * Sizes are the on-disk size of the quantized ggml weights.
 */
export type ModelQuality = "draft" | "balanced" | "accurate";

export interface SpeechModel {
  /** Stable id, also the filename stem on disk. */
  id: string;
  name: string;
  description: string;
  /** Download size in bytes. */
  bytes: number;
  quality: ModelQuality;
  /** Multilingual or English-only. */
  languages: "en" | "multilingual";
  /** Rough realtime factor on Apple silicon (higher = faster than realtime). */
  realtimeFactor: number;
  url: string;
  sha256?: string;
  recommended?: boolean;
}

const HF = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main";

export const SPEECH_MODELS: SpeechModel[] = [
  {
    id: "tiny.en-q5_1",
    name: "Tiny (English)",
    description: "Fastest option. Great for short commands on battery.",
    bytes: 32_600_000,
    quality: "draft",
    languages: "en",
    realtimeFactor: 32,
    url: `${HF}/ggml-tiny.en-q5_1.bin`,
  },
  {
    id: "base.en-q5_1",
    name: "Base (English)",
    description: "Good accuracy for everyday dictation with a tiny footprint.",
    bytes: 59_700_000,
    quality: "balanced",
    languages: "en",
    realtimeFactor: 20,
    url: `${HF}/ggml-base.en-q5_1.bin`,
    recommended: true,
  },
  {
    id: "small.en-q5_1",
    name: "Small (English)",
    description: "Noticeably better punctuation and proper nouns.",
    bytes: 181_000_000,
    quality: "accurate",
    languages: "en",
    realtimeFactor: 9,
    url: `${HF}/ggml-small.en-q5_1.bin`,
  },
  {
    id: "medium-q5_0",
    name: "Medium (multilingual)",
    description: "99 languages, highest accuracy. Needs ~2 GB of RAM.",
    bytes: 539_000_000,
    quality: "accurate",
    languages: "multilingual",
    realtimeFactor: 3,
    url: `${HF}/ggml-medium-q5_0.bin`,
  },
  {
    id: "large-v3-turbo-q5_0",
    name: "Large v3 Turbo",
    description: "Near large-v3 quality at a fraction of the cost.",
    bytes: 574_000_000,
    quality: "accurate",
    languages: "multilingual",
    realtimeFactor: 6,
    url: `${HF}/ggml-large-v3-turbo-q5_0.bin`,
  },
];

export function findModel(id: string): SpeechModel | undefined {
  return SPEECH_MODELS.find((m) => m.id === id);
}
