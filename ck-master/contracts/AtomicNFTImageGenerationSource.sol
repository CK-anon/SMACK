// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @dev An "Atomic" NFT contract that requires a proof of complete knowledge from each token recipient.
 * Generating the same images requires a large `constants.py` file containing the elements.
 */
contract AtomicNFTImageGenerationSource {
    string public sourceCodeCmapUtilsPy = "import random\n\
from samila.functions import is_valid_color as is_valid_color\n\
\n\
def rand_cmap(nlabels, type='bright', verbose=True):\n\
    \"\"\"\n\
    Creates a random colormap to be used together with matplotlib. Useful for segmentation tasks\n\
    :param nlabels: Number of labels (size of colormap)\n\
    :param type: 'bright' for strong colors, 'soft' for pastel colors\n\
    :param verbose: Prints the number of labels and shows the colormap. True or False\n\
    :return: colormap for matplotlib\n\
    \"\"\"\n\
    import colorsys\n\
    import numpy as np\n\
\n\
\n\
    if type not in ('bright', 'soft'):\n\
        print ('Please choose \"bright\" or \"soft\" for type')\n\
        return\n\
\n\
    if verbose:\n\
        print('Number of labels: ' + str(nlabels))\n\
\n\
    # Generate color map for bright colors, based on hsv\n\
    if type == 'bright':\n\
        randHSVcolors = [(np.random.uniform(low=0.0, high=1),\n\
                          np.random.uniform(low=0.0, high=1),\n\
                          np.random.uniform(low=0.0, high=1)) for i in range(nlabels)]\n\
\n\
        # Convert HSV list to RGB\n\
        randRGBcolors = []\n\
        for HSVcolor in randHSVcolors:\n\
            randRGBcolor = colorsys.hsv_to_rgb(HSVcolor[0], HSVcolor[1], HSVcolor[2])\n\
            if is_valid_color(randRGBcolor):\n\
                randRGBcolors.append(randRGBcolor)\n\
\n\
\n\
    # Generate soft pastel colors, by limiting the RGB spectrum\n\
    if type == 'soft':\n\
        low = 0.6\n\
        high = 0.95\n\
        randRGBcolors = list(filter(is_valid_color, [(np.random.uniform(low=low, high=high) ** 2,\n\
                          np.random.uniform(low=low, high=high) ** 2,\n\
                          np.random.uniform(low=low, high=high) ** 2) for i in range(nlabels)]))\n\
\n\
\n\
    for color in randRGBcolors:\n\
        if len(color) != 3:\n\
            randRGBcolors.remove(color)\n\
\n\
    return randRGBcolors\n\
\n\
\n\
def get_random_cmap(length=20):\n\
    new_cmap = rand_cmap(int(length/2), type=random.choice(['soft', 'bright']))\n\
    new_cmap = new_cmap + rand_cmap(int(length/5), type=random.choice(['soft', 'bright']))\n\
    random.shuffle(new_cmap)\n\
    return new_cmap\n\
";

    string public sourceCodeAtomicNftPy = "from PIL import Image\n\
import math, random\n\
from samila import GenerativeImage, Projection\n\
import os\n\
from cmap_utils import get_random_cmap\n\
from constants import ELEMENTS\n\
\n\
\n\
def f1(x, y):\n\
    result = random.uniform(-1,1) * x**2  - math.sin(y**2) + abs(y-x)\n\
    return result\n\
\n\
def f2(x, y):\n\
    result = random.uniform(-1,1) * y**3 - math.cos(x**2) + 2*x\n\
    return result\n\
\n\
\n\
def get_image(seeds, save_to_folder, colors):\n\
    \"\"\" Fully deterministic function for reproducibly generating a single\n\
        Atomic NFT PNG from a list of random seeds. \"\"\"\n\
    os.system(\"mkdir -p %s\" % (save_to_folder))\n\
    open(\"%s/data\" % (save_to_folder), 'w').write(\"%s\\n%s\" % (str(seeds), str(colors)))\n\
    for seed_index in range(len(seeds)):\n\
        # Generate component images, one for each seed. Save each component locally.\n\
        seed = seeds[seed_index]\n\
        g = GenerativeImage(f1, f2)\n\
        g.generate(seed=seed)\n\
        print(\"Using\", colors[seed_index])\n\
        g.plot(projection=Projection.POLAR, color=colors[seed_index], bgcolor=\"transparent\")\n\
        g.save_image('%s/seed_%d_%s.png' % (save_to_folder, seed_index, seed), depth=6)\n\
\n\
    # Merge components into a single transparent PNG\n\
    background = Image.open('%s/seed_0_%s.png' % (save_to_folder, seeds[0]))\n\
    for seed_index in range(1, len(seeds)):\n\
        foreground = Image.open(\"%s/seed_%d_%s.png\" % (save_to_folder, seed_index, seeds[seed_index]))\n\
        background.paste(foreground, (0, 0), foreground)\n\
    background.save(\"%s/final_nft.png\" % (save_to_folder))\n\
    print(\"Saved complete NFT to %s\" % (save_to_folder))\n\
\n\
\n\
# hardcoded seed = deterministic generation\n\
main_random = random.Random(69420)\n\
# generate 1k contracts\n\
for nft_num in range(0, 200):\n\
    depth = int(main_random.random() * 8) + 1\n\
    print(\"Depth\", depth)\n\
    seeds = []\n\
    chosen_colors = []\n\
    for i in range(0, depth):\n\
        seed = int(10000000000000000000000000000000000000000000000 * main_random.random())\n\
        seeds.append(seed)\n\
        chosen_colors.append(random.Random(seed).choice(ELEMENTS))\n\
        main_random = random.Random(seed)\n\
    get_image(seeds, \"nfts/atomic_nfts_%d\" % (nft_num), chosen_colors)\n\
\n\
    print(\"Finished NFT\", nft_num)\n\
";
}
