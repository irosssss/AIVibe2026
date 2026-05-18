// backend/functions/image-gen/index.js
// Генерация изображений интерьеров через Apify Image Generation Actor

import { runActor } from '../../shared/apify-client.js';
import { getSecrets } from '../../shared/secrets.js';

export const handler = async (event, context) => {
  await getSecrets();
  const { style, roomType, colorPalette, userId } = JSON.parse(event.body ?? '{}');

  if (!style || !userId) {
    return { statusCode: 400, body: JSON.stringify({ error: 'style and userId required' }) };
  }

  const STYLE_EN = {
    modern: 'modern contemporary interior, clean lines, neutral tones',
    minimalist: 'minimalist interior, white walls, functional, negative space',
    loft: 'loft style, exposed brick, metal elements, industrial',
    scandinavian: 'scandinavian interior, light wood, white, cozy, plants',
    classic_russian: 'classic interior, ornate details, rich fabrics, symmetry',
    eclectic: 'eclectic interior, mixed styles, bold accents',
    vintage: 'vintage interior, warm tones, antique furniture',
    professional: 'professional home office, dark accents, formal',
  };

  const ROOM_EN = {
    living_room: 'living room',
    bedroom: 'bedroom',
    kitchen: 'kitchen',
    bathroom: 'bathroom',
    office: 'home office',
    dining_room: 'dining room',
    hallway: 'hallway',
    child_room: "children's room",
  };

  const styleDesc = STYLE_EN[style] ?? style;
  const roomDesc = ROOM_EN[roomType] ?? roomType;
  const palette = colorPalette ? `, color palette: ${colorPalette}` : '';

  const prompt = `${styleDesc}, ${roomDesc}${palette}, photorealistic interior photography, 8K, natural lighting, architectural digest quality`;

  const results = await runActor(
    'apify/image-generation-agent',
    {
      prompt,
      negativePrompt: 'lowres, blurry, ugly, deformed, cartoon',
      width: 1024,
      height: 768,
      numberOfImages: 2,
    },
    { timeoutSecs: 90, memoryMbytes: 1024 }
  );

  const images = results.filter(r => r.imageUrl).map(r => ({ url: r.imageUrl, prompt }));

  return { statusCode: 200, body: JSON.stringify({ images }) };
};
