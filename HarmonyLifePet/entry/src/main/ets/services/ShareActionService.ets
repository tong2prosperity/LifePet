import { CatalogPet } from '../models/CatalogModels';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';

export interface ShareActionResult {
  ok: boolean;
  message: string;
}

export class ShareActionService {
  async saveCatalogCard(
    context: common.UIAbilityContext,
    pet: CatalogPet,
    pixelMap: image.PixelMap | undefined,
    authorized: boolean
  ): Promise<ShareActionResult> {
    if (!authorized) {
      return {
        ok: false,
        message: '未获得相册保存授权'
      };
    }
    if (!pixelMap) {
      return {
        ok: false,
        message: '分享卡截图失败'
      };
    }
    let file: fileIo.File | undefined = undefined;
    const imagePackerApi: image.ImagePacker = image.createImagePacker();
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png');
      file = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      await imagePackerApi.packToFile(pixelMap, file.fd, {
        format: 'image/png',
        quality: 100
      });
      return {
        ok: true,
        message: `${pet.name} 分享卡已保存到相册`
      };
    } catch (error) {
      return {
        ok: false,
        message: `保存失败：${this.errorMessage(error)}`
      };
    } finally {
      if (file) {
        await fileIo.close(file.fd);
      }
      imagePackerApi.release();
    }
  }

  async shareCatalogCard(context: common.UIAbilityContext, pet: CatalogPet): Promise<ShareActionResult> {
    return this.openSystemShare(context, `${pet.name} 的 LifePet 卡片`, this.catalogShareText(pet));
  }

  async copyInviteCode(code: string): Promise<ShareActionResult> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code);
      await pasteboard.getSystemPasteboard().setData(data);
      return {
        ok: true,
        message: `已复制 ${code}`
      };
    } catch (error) {
      return {
        ok: false,
        message: `复制失败：${this.errorMessage(error)}`
      };
    }
  }

  async shareInviteCode(context: common.UIAbilityContext, code: string): Promise<ShareActionResult> {
    const result = await this.openSystemShare(context, 'LifePet 邀请码', this.inviteShareText(code));
    return result.ok ? { ok: true, message: '已生成分享卡' } : result;
  }

  private async openSystemShare(
    context: common.UIAbilityContext,
    title: string,
    content: string
  ): Promise<ShareActionResult> {
    try {
      const data = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        title,
        description: content,
        content
      });
      const controller = new systemShare.ShareController(data);
      await controller.show(context);
      return {
        ok: true,
        message: '已打开系统分享面板'
      };
    } catch (error) {
      return {
        ok: false,
        message: `分享失败：${this.errorMessage(error)}`
      };
    }
  }

  private catalogShareText(pet: CatalogPet): string {
    const dayCopy = pet.isAlive ? `第 ${pet.days} 天` : `陪伴 ${pet.totalDays} 天`;
    return [
      `LifePet · ${pet.name}`,
      dayCopy,
      `体力 ${pet.stats.vitality} / 精力 ${pet.stats.energy} / 心情 ${pet.stats.mood}`,
      '邀请你一起照顾自己的身体。'
    ].join('\n');
  }

  private inviteShareText(code: string): string {
    return [
      '来 LifePet 加入我的双人空间',
      `邀请码：${code}`,
      '一起用健康数据养一只电子生命。'
    ].join('\n');
  }

  private errorMessage(error: unknown): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '系统能力暂不可用';
  }
}
