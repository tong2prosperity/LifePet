import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { CatalogPet, DeathType } from '../models/CatalogModels';

type RawFileDescriptor = {
  fd: number;
  offset: number;
  length: number;
};

export function memorialAudioForPet(pet: CatalogPet): string {
  if (pet.isRare) {
    return 'audio/memorial_meme_mascot_ascend_ultra.mp3';
  }
  switch (pet.deathType) {
    case DeathType.Chronic:
      return 'audio/memorial_meme_vaporwave_memorial.mp3';
    case DeathType.Acute:
      return 'audio/memorial_meme_anime_game_farewell.mp3';
    case DeathType.Starve:
      return 'audio/memorial_meme_shoujo_melancholy.mp3';
    case DeathType.Illness:
      return 'audio/memorial_meme_kawaii_pet_heaven.mp3';
    case DeathType.Natural:
    default:
      return 'audio/memorial_meme_pixel_pet_ascend.mp3';
  }
}

export class MemorialAudioPlayer {
  private player: media.AVPlayer | null = null;
  private source: string = '';
  isPlaying: boolean = false;

  async play(context: common.UIAbilityContext, rawfilePath: string): Promise<void> {
    await this.stop();
    const player = await media.createAVPlayer();
    this.player = player;
    this.source = rawfilePath;
    this.bindPlayerEvents(player);

    const rawFd = await context.resourceManager.getRawFd(rawfilePath) as RawFileDescriptor;
    player.fdSrc = {
      fd: rawFd.fd,
      offset: rawFd.offset,
      length: rawFd.length
    };
    await player.prepare();
    await player.play();
    this.isPlaying = true;
  }

  async pause(): Promise<void> {
    if (!this.player) {
      this.isPlaying = false;
      return;
    }
    try {
      await this.player.pause();
    } finally {
      this.isPlaying = false;
    }
  }

  async stop(): Promise<void> {
    const player = this.player;
    this.player = null;
    this.source = '';
    this.isPlaying = false;
    if (!player) {
      return;
    }
    try {
      await player.stop();
    } catch (_) {
      // AVPlayer may already be idle/completed; release is still required.
    }
    try {
      await player.release();
    } catch (_) {
      // Release errors should not block UI state cleanup.
    }
  }

  private bindPlayerEvents(player: media.AVPlayer): void {
    player.on('stateChange', (state: string) => {
      if (state === 'completed' || state === 'stopped' || state === 'released' || state === 'error') {
        this.isPlaying = false;
      }
    });
    player.on('error', () => {
      this.isPlaying = false;
    });
  }
}
