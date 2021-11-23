#version 330 core

uniform sampler2D texture0;

in vec2 vertexTextureCoordinate;

out vec4 fragmentColor;

void main()
{
    fragmentColor = texture(texture0, vertexTextureCoordinate);
}
