module gamutextension;

import gamut : Image, PixelType;
import imgui.colorscheme : RGBA;

void setPixel(Image* image, int x, int y, ref RGBA color)
{
    ubyte[] bytes = cast(ubyte[]) image.scanline(y);
    const reminder = 255 - color.a;
    if (image.type == PixelType.rgb8)
    {
        const idx = x * 3;
        bytes[idx + 0] = cast(ubyte)((bytes[idx + 0] * reminder + color.r * color.a) / 255);
        bytes[idx + 1] = cast(ubyte)((bytes[idx + 1] * reminder + color.g * color.a) / 255);
        bytes[idx + 2] = cast(ubyte)((bytes[idx + 2] * reminder + color.b * color.a) / 255);
    }
    else if (image.type == PixelType.rgba8)
    {
        const idx = x * 4;
        bytes[idx + 0] = cast(ubyte)((bytes[idx + 0] * reminder + color.r * color.a) / 255);
        bytes[idx + 1] = cast(ubyte)((bytes[idx + 1] * reminder + color.g * color.a) / 255);
        bytes[idx + 2] = cast(ubyte)((bytes[idx + 2] * reminder + color.b * color.a) / 255);
        bytes[idx + 3] = cast(ubyte)((bytes[idx + 3] * reminder + color.a * color.a) / 255);
    }
}

void drawRect(Image* image, int x, int y, int width, int height, ref RGBA color)
{
    for (int j = y; j < y + height; ++j)
    {
        image.setPixel(x, j, color);
        image.setPixel(x + width - 1, j, color);
    }
    for (int i = x + 1; i < x + width - 1; ++i)
    {
        image.setPixel(i, y, color);
        image.setPixel(i, y + height - 1, color);
    }
}
