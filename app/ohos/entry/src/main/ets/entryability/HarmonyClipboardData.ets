import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

/// Discard only copies created by a read whose dialog was dismissed mid-copy.
export function discardClipboardCopies(data: Map<string, Object>): void {
  const paths = (data.get('paths') as string[] | undefined) ?? [];
  const directories = (data.get('directories') as string[] | undefined) ?? [];
  const imagePath = data.get('path') as string | undefined;
  const items = paths.concat(directories);
  if (imagePath) items.push(imagePath);
  for (const path of items) {
    try { fs.rmdirSync(path.substring(0, path.lastIndexOf('/'))); }
    catch (error) { console.error('Cannot clean dismissed clipboard copy: ' + String(error)); }
  }
}

/// Called only after the user has authorized reading through PasteButton.
export async function readAuthorizedClipboard(filesDir: string): Promise<Map<string, Object>> {
  const store = filesDir + '/localsend-clipboard-imports';
  const data = await pasteboard.getSystemPasteboard().getData();
  const paths: string[] = [];
  const directories: string[] = [];
  let failed = 0;
  let hasFileUri = false;
  for (let i = 0; i < data.getRecordCount(); i++) {
    let directory = '';
    try {
      const record = data.getRecord(i);
      if (!record.getValidTypes([pasteboard.MIMETYPE_TEXT_URI]).includes(pasteboard.MIMETYPE_TEXT_URI)) continue;
      const uri = await record.getData(pasteboard.MIMETYPE_TEXT_URI) as string;
      if (uri.startsWith('http://') || uri.startsWith('https://')) continue;
      hasFileUri = true;
      if (!uri.startsWith('file://')) throw new Error('Unsupported file URI');
      directory = fs.mkdtempSync(store + '/localsend-clipboard-file-XXXXXX');
      await fs.copy(uri, fileUri.getUriFromPath(directory));
      const entries = fs.listFileSync(directory);
      if (entries.length !== 1) throw new Error('Invalid copied item');
      const path = directory + '/' + entries[0];
      const stat = fs.lstatSync(path);
      if (stat.isSymbolicLink()) throw new Error('Unsupported symbolic link');
      if (stat.isFile()) paths.push(path);
      else if (stat.isDirectory()) directories.push(path);
      else throw new Error('Unsupported copied item');
    } catch (error) {
      hasFileUri = true;
      failed++;
      console.error('Cannot import clipboard file: ' + String(error));
      // This temporary directory belongs only to this one import.
      if (directory) {
        try { fs.rmdirSync(directory); }
        catch (cleanupError) { console.error('Cannot clean clipboard copy: ' + String(cleanupError)); }
      }
    }
  }
  if (hasFileUri) {
    const result = new Map<string, Object>();
    result.set('paths', paths);
    result.set('directories', directories);
    result.set('failed', failed);
    return result;
  }
  const pixelMap = data.getPrimaryPixelMap();
  if (pixelMap) {
    const directory = fs.mkdtempSync(store + '/localsend-clipboard-XXXXXX');
    const path = directory + '/clipboard.png';
    let file: fs.File | undefined;
    const packer = image.createImagePacker();
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      await packer.packToFile(pixelMap, file.fd, { format: 'image/png', quality: 100 });
      const result = new Map<string, Object>();
      result.set('path', path);
      return result;
    } catch (error) {
      if (file) { fs.closeSync(file.fd); file = undefined; }
      try { fs.unlinkSync(path); } catch (_) {}
      throw new Error(String(error));
    } finally {
      if (file) fs.closeSync(file.fd);
      try { await packer.release(); } finally { await pixelMap.release(); }
    }
  }
  const text = data.getPrimaryText();
  if (text !== undefined && text !== null) {
    const result = new Map<string, Object>();
    result.set('text', text);
    return result;
  }
  return new Map<string, Object>();
}
