#version 330 core

uniform sampler2D texture0;

in vec4 vertexColor;
in vec2 vertexTextureCoordinate;

out vec4 fragmentColor;

void main()
{
    fragmentColor = vertexColor * texture(texture0, vertexTextureCoordinate);
}
