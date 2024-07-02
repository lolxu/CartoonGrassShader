# Unity Cartoon Grass Shader

This is a relatively complex grass shader that uses the following techniques to produce cartoonish grass like in Breath of the Wild:
* Tesselation Shader to add vertices on meshes to spawn more grass
* Geometric shader to procedurally create grass blade segments
* Sampling textures to create wind effect on grass
* Sampling textures to dynamically cull and paint grass on surfaces
* Custom fragment shader to receive shadow on grass

## Here's a screenshot in Unity:
![image](https://github.com/lolxu/CartoonGrassShader/assets/14366340/a9b8febe-4981-4b7f-aee0-2746c0097ffb)
